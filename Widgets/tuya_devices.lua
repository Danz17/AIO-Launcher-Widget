-- name = "Tuya Smart Devices"
-- description = "Monitor and control Tuya smart devices"
-- foldable = "true"

-- CONFIGURATION - EDIT YOUR CREDENTIALS HERE
local CONFIG = {
    accessId = "",  -- Your Tuya Access ID
    accessSecret = "",  -- Your Tuya Access Secret
    region = "us",  -- us, eu, cn, in
    deviceIds = {},  -- List of device IDs to monitor
    oauthToken = nil,  -- OAuth access token (auto-refreshed)
    tokenExpiry = 0,  -- Token expiry timestamp
    deviceGroups = {},  -- Device grouping by room/category
    scenes = {}  -- Predefined scenes
}

-- UTILITY FUNCTIONS

local function getBaseURL()
    local urls = {
        us = "https://openapi.tuyaus.com",
        eu = "https://openapi.tuyaeu.com",
        cn = "https://openapi.tuyacn.com",
        ["in"] = "https://openapi.tuyain.com"
    }
    return urls[CONFIG.region] or urls.us
end

local function getDeviceIcon(category)
    if not category then return "📱" end
    if category:find("light") then return "💡" end
    if category:find("switch") then return "🔌" end
    if category:find("curtain") then return "🪟" end
    if category:find("thermostat") then return "🌡️" end
    if category:find("fan") then return "🌀" end
    return "📱"
end

local function getDeviceStatus(device)
    if not device.online then
        return { text = "Offline", icon = "🔴" }
    end
    
    -- Check for switch/light status
    if device.status then
        for _, s in ipairs(device.status) do
            if s.code == "switch_1" or s.code == "switch" then
                if s.value then
                    return { text = "On", icon = "🟢" }
                else
                    return { text = "Off", icon = "⚪" }
                end
            end
        end
    end
    
    return { text = "Online", icon = "🟢" }
end

-- HMAC-SHA256 Implementation for Tuya API
-- Uses system API for crypto operations

local function hmacSHA256(key, message)
    if system and system.hmac_sha256 then
        local result = system:hmac_sha256(key, message)
        if result then
            return result
        end
    end
    -- Fallback: return error indicator
    return nil
end

local function generateSign(method, path, timestamp, body)
    local stringToSign = method .. "\n\n\n" .. timestamp .. "\n" .. path
    if body and body ~= "" then
        stringToSign = stringToSign .. "\n" .. body
    end
    local sign = hmacSHA256(CONFIG.accessSecret, stringToSign)
    if not sign then
        error("Failed to generate HMAC-SHA256 signature")
    end
    return sign
end

-- OAuth Token Management

local function getOAuthToken(callback)
    -- Check if token is still valid
    local now = os.time()
    if CONFIG.oauthToken and CONFIG.tokenExpiry > now + 300 then
        -- Token valid for at least 5 more minutes
        callback(CONFIG.oauthToken, nil)
        return
    end
    
    -- Need to refresh token
    if not CONFIG.accessId or CONFIG.accessId == "" then
        callback(nil, "Not configured")
        return
    end
    
    local baseURL = getBaseURL()
    local timestamp = tostring(math.floor(os.time() * 1000))
    local endpoint = "/v1.0/token?grant_type=1"
    local sign = generateSign("GET", endpoint, timestamp, nil)
    
    local headers = {
        ["client_id"] = CONFIG.accessId,
        ["t"] = timestamp,
        ["sign_method"] = "HMAC-SHA256",
        ["sign"] = sign
    }
    
    local url = baseURL .. endpoint
    
    http:get(url, function(data, code)
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res and res.success and res.result then
                CONFIG.oauthToken = res.result.access_token
                CONFIG.tokenExpiry = now + (res.result.expire_time or 7200)  -- Default 2 hours
                callback(CONFIG.oauthToken, nil)
                return
            end
        end
        callback(nil, "Token refresh failed")
    end, headers)
end

-- TUYA API FUNCTIONS

local function tuyaRequest(method, endpoint, body, callback)
    if not CONFIG.accessId or CONFIG.accessId == "" then
        callback(nil, "Not configured")
        return
    end
    
    -- Get OAuth token first
    getOAuthToken(function(token, tokenErr)
        if tokenErr then
            callback(nil, tokenErr)
            return
        end
        
        local baseURL = getBaseURL()
        local timestamp = tostring(math.floor(os.time() * 1000))
        local sign = generateSign(method, endpoint, timestamp, body)
        
        local headers = {
            ["client_id"] = CONFIG.accessId,
            ["access_token"] = token,
            ["t"] = timestamp,
            ["sign_method"] = "HMAC-SHA256",
            ["sign"] = sign,
            ["Content-Type"] = "application/json"
        }
        
        makeRequest(method, endpoint, body, headers, callback)
    end)
end

local function makeRequest(method, endpoint, body, headers, callback)
    local baseURL = getBaseURL()
    local url = baseURL .. endpoint
    
    if method == "GET" then
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res then
                    if res.success == false then
                        callback(nil, res.msg or "API error")
                        return
                    end
                    callback(res.result, nil)
                    return
                end
            end
            callback(nil, "Request failed: " .. tostring(code))
        end, headers)
    else
        http:post(url, body or "", function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res then
                    if res.success == false then
                        callback(nil, res.msg or "API error")
                        return
                    end
                    callback(res.result, nil)
                    return
                end
            end
            callback(nil, "Request failed: " .. tostring(code))
        end, headers)
    end
end

local function getDevices(callback)
    tuyaRequest("GET", "/v1.0/devices", nil, function(result, err)
        if err then
            callback(nil, err)
            return
        end
        if result and result.list then
            callback(result.list, nil)
        else
            callback({}, nil)
        end
    end)
end

-- Device discovery: Auto-discover all devices from account
local function discoverDevices(callback)
    if not CONFIG.accessId or CONFIG.accessId == "" then
        callback(nil, "Not configured")
        return
    end
    
    -- Get all devices
    getDevices(function(devices, err)
        if err then
            callback(nil, err)
            return
        end
        
        -- Update CONFIG.deviceIds with discovered devices
        if devices and #devices > 0 then
            local discoveredIds = {}
            for _, device in ipairs(devices) do
                if device.id then
                    table.insert(discoveredIds, device.id)
                end
            end
            
            -- Merge with existing config (don't overwrite manually added)
            for _, id in ipairs(discoveredIds) do
                local found = false
                for _, existingId in ipairs(CONFIG.deviceIds) do
                    if existingId == id then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(CONFIG.deviceIds, id)
                end
            end
            
            callback(discoveredIds, nil)
        else
            callback({}, nil)
        end
    end)
end

-- MAIN FUNCTION

function on_resume()
    if not CONFIG.accessId or CONFIG.accessId == "" then
        ui:show_text("❌ Not configured\n\nSet accessId and accessSecret\nin the configuration section\n\nLong press for help")
        return
    end
    
    ui:show_text("⏳ Loading devices...")
    
    -- Auto-discover devices if deviceIds is empty
    if #CONFIG.deviceIds == 0 then
        discoverDevices(function(discoveredIds, discoverErr)
            if discoverErr then
                -- Continue with regular device fetch even if discovery fails
                getDevices(function(devices, err)
                    handleDeviceResponse(devices, err)
                end)
            else
                -- Discovery successful, now fetch device details
                getDevices(function(devices, err)
                    handleDeviceResponse(devices, err)
                end)
            end
        end)
    else
        -- Use configured device IDs
        getDevices(function(devices, err)
            handleDeviceResponse(devices, err)
        end)
    end
end

function handleDeviceResponse(devices, err)
    if err then
        ui:show_text("❌ Connection failed\n\n" .. err .. "\n\nCheck credentials/region\n\nLong press to retry")
        return
    end
    
    if not devices or #devices == 0 then
        ui:show_text("📱 No devices found\n\nAdd devices to your Tuya account\nor check device IDs in config\n\nLong press to discover")
        return
    end
    
    showDevices(devices)
end

-- Group devices by category/room
local function groupDevices(devices)
    local groups = {}
    for _, device in ipairs(devices) do
        local category = device.category or "other"
        local room = device.room or "default"
        local groupKey = room .. "/" .. category
        
        if not groups[groupKey] then
            groups[groupKey] = {}
        end
        table.insert(groups[groupKey], device)
    end
    return groups
end

-- Get energy consumption for device
local function getEnergyConsumption(device)
    if device.status then
        for _, s in ipairs(device.status) do
            if s.code == "cur_power" or s.code == "power" then
                return tonumber(s.value) or 0
            end
        end
    end
    return nil
end

function showDevices(devices)
    local onlineCount = 0
    local onCount = 0
    local totalEnergy = 0
    
    -- Group devices if enabled
    local useGroups = CONFIG.deviceGroups and #CONFIG.deviceGroups > 0
    local groups = useGroups and groupDevices(devices) or nil
    
    for _, device in ipairs(devices) do
        if device.online then
            onlineCount = onlineCount + 1
        end
        
        local status = getDeviceStatus(device)
        if status.text == "On" then
            onCount = onCount + 1
        end
        
        -- Sum energy consumption
        local energy = getEnergyConsumption(device)
        if energy then
            totalEnergy = totalEnergy + energy
        end
    end
    
    local o = "📱 Tuya Devices (" .. #devices .. ")\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    o = o .. "\n🟢 " .. onlineCount .. " Online  💡 " .. onCount .. " On\n"
    
    if totalEnergy > 0 then
        o = o .. "⚡ Power: " .. string.format("%.1f", totalEnergy) .. "W\n"
    end
    
    if useGroups and groups then
        o = o .. "\n📁 By Group:\n"
        local groupCount = 0
        for groupKey, groupDevs in pairs(groups) do
            if groupCount < 5 then
                o = o .. "  " .. groupKey .. ": " .. #groupDevs .. "\n"
                groupCount = groupCount + 1
            end
        end
    else
        o = o .. "\nDevices:\n"
        local maxShow = math.min(#devices, 8)
        for i = 1, maxShow do
            local device = devices[i]
            local icon = getDeviceIcon(device.category)
            local status = getDeviceStatus(device)
            local name = (device.name or "Device"):sub(1, 15)
            local padding = string.rep(" ", 15 - #name)
            
            local energy = getEnergyConsumption(device)
            local energyStr = energy and (" (" .. string.format("%.0f", energy) .. "W)") or ""
            
            o = o .. icon .. " " .. name .. padding .. " " .. status.icon .. " " .. status.text .. energyStr .. "\n"
        end
        
        if #devices > 8 then
            o = o .. "\n  +" .. (#devices - 8) .. " more\n"
        end
    end
    
    o = o .. "\n🔗 Tap: Refresh │ Long: Control"
    
    ui:show_text(o)
end

function on_click()
    on_resume()
end

local function controlDevice(deviceId, command, value, callback)
    if not CONFIG.accessId or CONFIG.accessId == "" then
        callback(false, "Not configured")
        return
    end
    
    local body = json:encode({
        commands = {{
            code = command,
            value = value
        }}
    })
    
    tuyaRequest("POST", "/v1.0/devices/" .. deviceId .. "/commands", body, function(result, err)
        if err then
            callback(false, err)
        else
            callback(true, nil)
        end
    end)
end

-- Batch control multiple devices
local function batchControlDevices(deviceIds, command, value, callback)
    local results = {}
    local pending = #deviceIds
    
    for _, deviceId in ipairs(deviceIds) do
        controlDevice(deviceId, command, value, function(success, err)
            table.insert(results, {deviceId = deviceId, success = success, error = err})
            pending = pending - 1
            if pending == 0 then
                callback(results)
            end
        end)
    end
end

-- Get scenes
local function getScenes(callback)
    tuyaRequest("GET", "/v1.0/scenes", nil, function(result, err)
        if err then
            callback(nil, err)
            return
        end
        if result and result.list then
            callback(result.list, nil)
        else
            callback({}, nil)
        end
    end)
end

-- Activate scene
local function activateScene(sceneId, callback)
    local body = json:encode({})
    tuyaRequest("POST", "/v1.0/scenes/" .. sceneId .. "/trigger", body, function(result, err)
        if err then
            callback(false, err)
        else
            callback(true, nil)
        end
    end)
end

-- RGB color control
local function setColor(deviceId, r, g, b, callback)
    -- Convert RGB to HSV (Tuya uses HSV)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local delta = max - min
    
    local h = 0
    if delta > 0 then
        if max == r then
            h = ((g - b) / delta) % 6
        elseif max == g then
            h = (b - r) / delta + 2
        else
            h = (r - g) / delta + 4
        end
    end
    h = math.floor(h * 60)
    if h < 0 then h = h + 360 end
    
    local s = max > 0 and (delta / max) or 0
    local v = max / 255
    
    -- Tuya color format: "0000000" (HSV in hex)
    local hsv = string.format("%03d%03d%03d", h, math.floor(s * 1000), math.floor(v * 1000))
    
    controlDevice(deviceId, "colour_data_v2", hsv, callback)
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Refresh Devices",
        "🔍 Discover Devices",
        "📋 Device List",
        "💡 Control Device",
        "🎬 Scenes",
        "⚡ Batch Control",
        "❌ Close"
    }, function(index)
        if index == 0 then
            on_resume()
        elseif index == 1 then
            ui:show_text("⏳ Discovering devices...")
            discoverDevices(function(discoveredIds, err)
                if err then
                    ui:show_text("❌ Discovery failed\n\n" .. err)
                elseif discoveredIds and #discoveredIds > 0 then
                    ui:show_text("✅ Found " .. #discoveredIds .. " devices\n\nDevice IDs updated in config\n\nTap to refresh")
                else
                    ui:show_text("📱 No devices found\n\nCheck Tuya account")
                end
            end)
        elseif index == 2 then
            getDevices(function(devices, err)
                if err or not devices or #devices == 0 then
                    system:toast("No devices available")
                else
                    local o = "📱 Devices (" .. #devices .. ")\n"
                    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                    for i, device in ipairs(devices) do
                        if i <= 10 then
                            local name = (device.name or "Device"):sub(1, 20)
                            local status = device.online and "🟢" or "🔴"
                            o = o .. status .. " " .. name .. "\n"
                        end
                    end
                    if #devices > 10 then
                        o = o .. "\n  +" .. (#devices - 10) .. " more"
                    end
                    ui:show_text(o)
                end
            end)
        elseif index == 3 then
            -- Control device menu
            getDevices(function(devices, err)
                if err or not devices or #devices == 0 then
                    system:toast("No devices available")
                else
                    local deviceMenu = {}
                    for i, device in ipairs(devices) do
                        if device.online and i <= 5 then
                            table.insert(deviceMenu, device.name or "Device " .. i)
                        end
                    end
                    if #deviceMenu == 0 then
                        system:toast("No online devices")
                    else
                        ui:show_context_menu(deviceMenu, function(selectedIdx)
                            if selectedIdx and selectedIdx > 0 and selectedIdx <= #deviceMenu then
                                local device = devices[selectedIdx]
                                -- Show control options
                                ui:show_context_menu({
                                    "💡 Toggle Switch",
                                    "🔆 Brightness: 50%",
                                    "🔆 Brightness: 100%",
                                    "🎨 Color: White",
                                    "❌ Cancel"
                                }, function(controlIdx)
                                    if controlIdx == 0 and device.id then
                                        -- Toggle switch
                                        controlDevice(device.id, "switch_1", true, function(success, err)
                                            if success then
                                                system:toast("Device toggled")
                                                on_resume()
                                            else
                                                system:toast("Failed: " .. (err or "Unknown"))
                                            end
                                        end)
                                    elseif controlIdx == 1 and device.id then
                                        controlDevice(device.id, "brightness", 50, function(success, err)
                                            if success then
                                                system:toast("Brightness set to 50%")
                                                on_resume()
                                            end
                                        end)
                                    elseif controlIdx == 2 and device.id then
                                        controlDevice(device.id, "brightness", 100, function(success, err)
                                            if success then
                                                system:toast("Brightness set to 100%")
                                                on_resume()
                                            end
                                        end)
                                    elseif controlIdx == 3 and device.id then
                                        -- Set color to white
                                        setColor(device.id, 255, 255, 255, function(success, err)
                                            if success then
                                                system:toast("Color set to white")
                                                on_resume()
                                            end
                                        end)
                                    end
                                end)
                            end
                        end)
                    end
                end
            end)
        elseif index == 4 then
            -- Scenes
            getScenes(function(scenes, err)
                if err or not scenes or #scenes == 0 then
                    system:toast("No scenes available")
                else
                    local sceneMenu = {}
                    for i, scene in ipairs(scenes) do
                        if i <= 5 then
                            table.insert(sceneMenu, scene.name or "Scene " .. i)
                        end
                    end
                    ui:show_context_menu(sceneMenu, function(sceneIdx)
                        if sceneIdx and sceneIdx > 0 and sceneIdx <= #scenes then
                            activateScene(scenes[sceneIdx].id, function(success, err)
                                if success then
                                    system:toast("Scene activated")
                                    on_resume()
                                else
                                    system:toast("Failed: " .. (err or "Unknown"))
                                end
                            end)
                        end
                    end)
                end
            end)
        elseif index == 5 then
            -- Batch control
            getDevices(function(devices, err)
                if err or not devices or #devices == 0 then
                    system:toast("No devices available")
                else
                    ui:show_context_menu({
                        "💡 Turn All On",
                        "⚪ Turn All Off",
                        "🔆 Set All Brightness 50%",
                        "❌ Cancel"
                    }, function(batchIdx)
                        if batchIdx == 0 then
                            local onlineIds = {}
                            for _, device in ipairs(devices) do
                                if device.online and device.id then
                                    table.insert(onlineIds, device.id)
                                end
                            end
                            batchControlDevices(onlineIds, "switch_1", true, function(results)
                                system:toast("Batch control completed")
                                on_resume()
                            end)
                        elseif batchIdx == 1 then
                            local onlineIds = {}
                            for _, device in ipairs(devices) do
                                if device.online and device.id then
                                    table.insert(onlineIds, device.id)
                                end
                            end
                            batchControlDevices(onlineIds, "switch_1", false, function(results)
                                system:toast("Batch control completed")
                                on_resume()
                            end)
                        elseif batchIdx == 2 then
                            local onlineIds = {}
                            for _, device in ipairs(devices) do
                                if device.online and device.id then
                                    table.insert(onlineIds, device.id)
                                end
                            end
                            batchControlDevices(onlineIds, "brightness", 50, function(results)
                                system:toast("Batch control completed")
                                on_resume()
                            end)
                        end
                    end)
                end
            end)
        end
    end)
end


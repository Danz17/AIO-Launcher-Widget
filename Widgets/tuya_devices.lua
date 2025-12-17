-- name = "Tuya Smart Devices"
-- description = "Monitor and control Tuya smart devices"
-- foldable = "true"

-- CONFIGURATION - EDIT YOUR CREDENTIALS HERE
local CONFIG = {
    accessId = "",  -- Your Tuya Access ID
    accessSecret = "",  -- Your Tuya Access Secret
    region = "us",  -- us, eu, cn, in
    deviceIds = {}  -- List of device IDs to monitor
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

-- HMAC-SHA256 Implementation (Simplified for Tuya API)
-- Note: This is a placeholder. In production, you would use a proper crypto library
-- For the emulator, the signature will be mocked

local function hmacSHA256(key, message)
    -- This is a placeholder that would need proper implementation
    -- In real AIO Launcher, you'd use a crypto library or Java bridge
    return "MOCK_SIGNATURE_FOR_TESTING"
end

local function generateSign(method, path, timestamp, body)
    local stringToSign = method .. "\n\n\n" .. timestamp .. "\n" .. path
    if body and body ~= "" then
        stringToSign = stringToSign .. "\n" .. body
    end
    return hmacSHA256(CONFIG.accessSecret, stringToSign)
end

-- TUYA API FUNCTIONS

local function tuyaRequest(method, endpoint, body, callback)
    if not CONFIG.accessId or CONFIG.accessId == "" then
        callback(nil, "Not configured")
        return
    end
    
    local baseURL = getBaseURL()
    local timestamp = tostring(math.floor(os.time() * 1000))
    local sign = generateSign(method, endpoint, timestamp, body)
    
    local headers = {
        ["client_id"] = CONFIG.accessId,
        ["t"] = timestamp,
        ["sign_method"] = "HMAC-SHA256",
        ["sign"] = sign,
        ["Content-Type"] = "application/json"
    }
    
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

-- MAIN FUNCTION

function on_resume()
    if not CONFIG.accessId or CONFIG.accessId == "" then
        ui:show_text("❌ Not configured\n\nSet accessId and accessSecret\nin the configuration section\n\nLong press for help")
        return
    end
    
    ui:show_text("⏳ Loading devices...")
    
    getDevices(function(devices, err)
        if err then
            ui:show_text("❌ Connection failed\n\n" .. err .. "\n\nCheck credentials/region\n\nLong press to retry")
            return
        end
        
        if not devices or #devices == 0 then
            ui:show_text("📱 No devices found\n\nAdd devices to your Tuya account\nor check device IDs in config\n\nLong press to retry")
            return
        end
        
        showDevices(devices)
    end)
end

function showDevices(devices)
    local onlineCount = 0
    local onCount = 0
    
    for _, device in ipairs(devices) do
        if device.online then
            onlineCount = onlineCount + 1
        end
        
        local status = getDeviceStatus(device)
        if status.text == "On" then
            onCount = onCount + 1
        end
    end
    
    local o = "📱 Tuya Devices (" .. #devices .. ")\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    o = o .. "\n🟢 " .. onlineCount .. " Online  💡 " .. onCount .. " On\n"
    o = o .. "\nDevices:\n"
    
    local maxShow = math.min(#devices, 8)
    for i = 1, maxShow do
        local device = devices[i]
        local icon = getDeviceIcon(device.category)
        local status = getDeviceStatus(device)
        local name = (device.name or "Device"):sub(1, 15)
        local padding = string.rep(" ", 15 - #name)
        
        o = o .. icon .. " " .. name .. padding .. " " .. status.icon .. " " .. status.text .. "\n"
    end
    
    if #devices > 8 then
        o = o .. "\n  +" .. (#devices - 8) .. " more\n"
    end
    
    o = o .. "\n🔗 Tap: Refresh │ Long: Control"
    
    ui:show_text(o)
end

function on_click()
    on_resume()
end

function on_long_click()
    on_resume()
end


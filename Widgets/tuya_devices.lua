-- name = "Tuya Smart Devices"
-- description = "Monitor and control Tuya smart devices"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    accessId = "",
    accessSecret = "",
    region = "us",  -- us, eu, cn, in
    deviceIds = {}
}

-- State
local state = {
    token = nil,
    tokenExpiry = 0,
    devices = {},
    error = nil
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

-- DISPLAY FUNCTION

local function showDevices()
    if state.error then
        ui:show_text("❌ Connection failed\n\n" .. state.error .. "\n\nCheck credentials/region\n\nLong press to retry")
        return
    end

    local devices = state.devices or {}

    if #devices == 0 then
        ui:show_text("📱 No devices found\n\nAdd devices to your Tuya account\nor check configuration\n\nLong press to refresh")
        return
    end

    local onlineCount = 0
    local onCount = 0
    local totalEnergy = 0

    for _, device in ipairs(devices) do
        if device.online then
            onlineCount = onlineCount + 1
        end

        local status = getDeviceStatus(device)
        if status.text == "On" then
            onCount = onCount + 1
        end

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

    o = o .. "\n🔗 Tap: Refresh │ Long: Options"
    ui:show_text(o)
end

-- NETWORK CALLBACKS

function on_network_result_token(body, code)
    if code ~= 200 or not body or body == "" then
        state.error = "Token request failed (HTTP " .. tostring(code) .. ")"
        showDevices()
        return
    end

    local ok, res = pcall(function() return json:decode(body) end)
    if not ok or not res or not res.success or not res.result then
        state.error = "Token request failed - invalid response"
        showDevices()
        return
    end

    state.token = res.result.access_token
    state.tokenExpiry = os.time() + (res.result.expire_time or 7200)
    state.error = nil

    -- Now fetch devices
    local baseURL = getBaseURL()
    http:get(baseURL .. "/v1.0/devices", "devices")
end

function on_network_error_token(err)
    state.error = err or "Network error during token request"
    showDevices()
end

function on_network_result_devices(body, code)
    if code ~= 200 or not body or body == "" then
        state.error = "Device request failed (HTTP " .. tostring(code) .. ")"
        showDevices()
        return
    end

    local ok, res = pcall(function() return json:decode(body) end)
    if not ok or not res then
        state.error = "Invalid device response"
        showDevices()
        return
    end

    if not res.success then
        state.error = res.msg or "API error"
        showDevices()
        return
    end

    state.error = nil
    if res.result and res.result.list then
        state.devices = res.result.list
    else
        state.devices = {}
    end

    showDevices()
end

function on_network_error_devices(err)
    state.error = err or "Network error"
    showDevices()
end

-- MAIN ENTRY POINTS

function on_resume()
    if not CONFIG.accessId or CONFIG.accessId == "" then
        ui:show_text("❌ Not configured\n\nSet accessId and accessSecret\nin the configuration section\n\nLong press for help")
        return
    end

    ui:show_text("⏳ Loading devices...")

    -- Reset state
    state.error = nil
    state.devices = {}

    -- Get OAuth token first
    local baseURL = getBaseURL()
    local tokenUrl = baseURL .. "/v1.0/token?grant_type=1"

    -- Note: Tuya API requires HMAC-SHA256 signature which is complex
    -- This simplified version may not work without proper signing
    http:get(tokenUrl, "token")
end

function on_click()
    on_resume()
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Refresh Devices",
        "🔍 Discover Devices",
        "📋 Device List",
        "💡 Toggle All On",
        "⚪ Toggle All Off",
        "❌ Close"
    })
end

function on_context_menu_click(idx)
    if idx == 0 then
        on_resume()
    elseif idx == 1 then
        ui:show_toast("Discovery started...")
        on_resume()
    elseif idx == 2 then
        if #state.devices == 0 then
            ui:show_toast("No devices available")
        else
            local o = "📱 Devices (" .. #state.devices .. ")\n"
            o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            for i, device in ipairs(state.devices) do
                if i <= 10 then
                    local name = (device.name or "Device"):sub(1, 20)
                    local status = device.online and "🟢" or "🔴"
                    o = o .. status .. " " .. name .. "\n"
                end
            end
            if #state.devices > 10 then
                o = o .. "\n  +" .. (#state.devices - 10) .. " more"
            end
            ui:show_text(o)
        end
    elseif idx == 3 then
        ui:show_toast("Batch on - configure devices first")
    elseif idx == 4 then
        ui:show_toast("Batch off - configure devices first")
    end
end

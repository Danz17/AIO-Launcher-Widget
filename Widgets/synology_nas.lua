-- name = "Synology NAS Monitor"
-- description = "Monitor Synology NAS storage and system status"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    ip = "192.168.1.100",
    port = 5000,
    username = "admin",
    password = "admin",
    useHTTPS = true,
    apiVersion = 1,
    storageAlertThreshold = 85,
    temperatureAlertThreshold = 70
}

-- State
local state = {
    sid = nil,
    sysInfo = nil,
    utilData = nil,
    storageData = nil,
    pending_requests = 0,
    error = nil
}

-- UTILITY FUNCTIONS

local function getBaseURL()
    local protocol = CONFIG.useHTTPS and "https" or "http"
    return protocol .. "://" .. CONFIG.ip .. ":" .. CONFIG.port
end

local function fmtBytes(bytes)
    if not bytes or bytes < 0 then return "0B" end
    if bytes >= 1e12 then return string.format("%.2fTB", bytes/1e12) end
    if bytes >= 1e9 then return string.format("%.2fGB", bytes/1e9) end
    if bytes >= 1e6 then return string.format("%.1fMB", bytes/1e6) end
    if bytes >= 1e3 then return string.format("%.0fKB", bytes/1e3) end
    return bytes .. "B"
end

local function progressBar(percent, width)
    width = width or 10
    local filled = math.floor((percent / 100) * width)
    return string.rep("█", filled) .. string.rep("░", width - filled)
end

local function fmtUptime(seconds)
    if not seconds then return "0s" end
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

-- URL encode
local function urlEncode(str)
    if not str then return "" end
    str = string.gsub(str, "([^%w%-_.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

-- DISPLAY FUNCTION

local function showInfo()
    if state.error then
        ui:show_text("❌ Connection failed\n\n" .. state.error .. "\n\nCheck IP/credentials:\n" .. CONFIG.ip .. ":" .. CONFIG.port .. "\n\nLong press to retry")
        return
    end

    if not state.sysInfo then
        ui:show_text("❌ No data received\n\nLong press to retry")
        return
    end

    local sysInfo = state.sysInfo
    local util = state.utilData
    local storage = state.storageData

    local model = sysInfo.model or "Synology NAS"
    local version = sysInfo.version_string or ""
    local uptime = sysInfo.uptime or 0

    local cpu = 0
    if util and util.cpu and util.cpu.user_load then
        cpu = tonumber(util.cpu.user_load) or 0
    end

    local memTotal = 0
    local memUsed = 0
    local memPercent = 0
    if util and util.memory then
        memTotal = tonumber(util.memory.total_kb) or 0
        memUsed = tonumber(util.memory.used_kb) or 0
        if memTotal > 0 then
            memPercent = math.floor((memUsed / memTotal) * 100)
        end
    end

    local o = "🖥 " .. model .. "\n"
    o = o .. "📌 DSM " .. version .. "\n"
    o = o .. "⏱ Uptime: " .. fmtUptime(uptime) .. "\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"

    o = o .. "\n💻 SYSTEM\n"
    o = o .. "CPU " .. progressBar(cpu, 10) .. " " .. cpu .. "%\n"
    o = o .. "RAM " .. progressBar(memPercent, 10) .. " " .. memPercent .. "%\n"
    o = o .. "    " .. fmtBytes(memUsed * 1024) .. " / " .. fmtBytes(memTotal * 1024) .. "\n"

    -- Temperature
    if util and util.temperature then
        local cpuTemp = tonumber(util.temperature.cpu) or 0
        if cpuTemp > 0 then
            o = o .. "\n🌡️ TEMPERATURE\n"
            o = o .. "CPU: " .. cpuTemp .. "°C"
            if cpuTemp > CONFIG.temperatureAlertThreshold then
                o = o .. " ⚠️"
            end
            o = o .. "\n"
        end
    end

    -- Storage
    if storage and storage.volumes then
        o = o .. "\n💾 STORAGE\n"
        for _, volume in ipairs(storage.volumes) do
            local used = tonumber(volume.used_size) or 0
            local total = tonumber(volume.total_size) or 0
            if total > 0 then
                local percent = math.floor((used / total) * 100)
                local name = volume.name or "Volume"
                o = o .. name .. ": " .. percent .. "%"
                if percent > CONFIG.storageAlertThreshold then
                    o = o .. " ⚠️"
                end
                o = o .. "\n"
            end
        end
    end

    -- Network
    if util and util.network then
        local rxBytes = tonumber(util.network.rx) or 0
        local txBytes = tonumber(util.network.tx) or 0
        o = o .. "\n🌐 NETWORK\n"
        o = o .. "↓ " .. fmtBytes(rxBytes) .. "/s  ↑ " .. fmtBytes(txBytes) .. "/s\n"
    end

    o = o .. "\n🔗 Tap: Open DSM │ Long: Refresh"
    ui:show_text(o)
end

local function checkAllDone()
    state.pending_requests = state.pending_requests - 1
    if state.pending_requests <= 0 then
        showInfo()
    end
end

-- NETWORK CALLBACKS

function on_network_result_login(body, code)
    if code ~= 200 or not body or body == "" then
        state.error = "Login failed (HTTP " .. tostring(code) .. ")"
        showInfo()
        return
    end

    local ok, res = pcall(function() return json:decode(body) end)
    if not ok or not res or not res.success or not res.data or not res.data.sid then
        state.error = "Login failed - invalid response"
        showInfo()
        return
    end

    state.sid = res.data.sid
    state.error = nil

    -- Now fetch system data
    state.pending_requests = 3
    local baseURL = getBaseURL()
    local sid = state.sid
    local ver = CONFIG.apiVersion

    http:get(baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System&version=" .. ver .. "&method=info&_sid=" .. sid, "sysinfo")
    http:get(baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System.Utilization&version=" .. ver .. "&method=get&_sid=" .. sid, "utilization")
    http:get(baseURL .. "/webapi/entry.cgi?api=SYNO.Storage.CGI.Storage&version=1&method=load_info&_sid=" .. sid, "storage")
end

function on_network_error_login(err)
    state.error = err or "Network error during login"
    showInfo()
end

function on_network_result_sysinfo(body, code)
    if code == 200 and body and body ~= "" then
        local ok, res = pcall(function() return json:decode(body) end)
        if ok and res and res.success and res.data then
            state.sysInfo = res.data
        end
    end
    checkAllDone()
end

function on_network_error_sysinfo(err)
    checkAllDone()
end

function on_network_result_utilization(body, code)
    if code == 200 and body and body ~= "" then
        local ok, res = pcall(function() return json:decode(body) end)
        if ok and res and res.success and res.data then
            state.utilData = res.data
        end
    end
    checkAllDone()
end

function on_network_error_utilization(err)
    checkAllDone()
end

function on_network_result_storage(body, code)
    if code == 200 and body and body ~= "" then
        local ok, res = pcall(function() return json:decode(body) end)
        if ok and res and res.success and res.data then
            state.storageData = res.data
        end
    end
    checkAllDone()
end

function on_network_error_storage(err)
    checkAllDone()
end

-- MAIN ENTRY POINTS

function on_resume()
    ui:show_text("⏳ Connecting to NAS...")

    -- Reset state
    state.sysInfo = nil
    state.utilData = nil
    state.storageData = nil
    state.error = nil
    state.pending_requests = 0

    -- Login first
    local baseURL = getBaseURL()
    local loginUrl = baseURL .. "/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=" ..
        urlEncode(CONFIG.username) .. "&passwd=" .. urlEncode(CONFIG.password) ..
        "&session=FileStation&format=sid"

    http:get(loginUrl, "login")
end

function on_click()
    local baseURL = getBaseURL()
    system:open_browser(baseURL)
end

function on_long_click()
    state.sid = nil
    on_resume()
end

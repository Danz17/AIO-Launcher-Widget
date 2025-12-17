-- name = "Synology NAS Monitor"
-- description = "Monitor Synology NAS storage and system status"
-- foldable = "true"

-- CONFIGURATION - EDIT YOUR CREDENTIALS HERE
local CONFIG = {
    ip = "192.168.1.100",
    port = 5000,
    username = "admin",
    password = "admin",
    useHTTPS = false
}

-- Base64 encode function
local function base64(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
        local r, byte = '', x:byte()
        for i = 8, 1, -1 do r = r .. (byte % 2^i - byte % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0) end
        return b:sub(c+1, c+1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

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

-- SYNOLOGY API FUNCTIONS

local session_sid = nil

local function synoLogin(callback)
    if session_sid then
        callback(session_sid)
        return
    end
    
    local baseURL = getBaseURL()
    local url = baseURL .. "/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=" .. CONFIG.username .. "&passwd=" .. CONFIG.password .. "&session=FileStation&format=sid"
    
    http:get(url, function(data, code)
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res and res.success and res.data and res.data.sid then
                session_sid = res.data.sid
                callback(session_sid)
                return
            end
        end
        callback(nil)
    end)
end

local function synoGetSystemInfo(callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil)
            return
        end
        
        local baseURL = getBaseURL()
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System&version=1&method=info&_sid=" .. sid
        
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res and res.success and res.data then
                    callback(res.data)
                    return
                end
            end
            callback(nil)
        end)
    end)
end

local function synoGetUtilization(callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil)
            return
        end
        
        local baseURL = getBaseURL()
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System.Utilization&version=1&method=get&_sid=" .. sid
        
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res and res.success and res.data then
                    callback(res.data)
                    return
                end
            end
            callback(nil)
        end)
    end)
end

-- MAIN FUNCTION

function on_resume()
    ui:show_text("⏳ Connecting to NAS...")
    
    -- Fetch system info first
    synoGetSystemInfo(function(sysInfo)
        if not sysInfo then
            ui:show_text("❌ Connection failed\n\nCheck IP/credentials:\n" .. CONFIG.ip .. ":" .. CONFIG.port .. "\n\nLong press for options")
            return
        end
        
        -- Then fetch utilization
        synoGetUtilization(function(util)
            if not util then
                showBasicInfo(sysInfo)
                return
            end
            
            showFullInfo(sysInfo, util)
        end)
    end)
end

function showBasicInfo(sysInfo)
    local model = sysInfo.model or "Unknown"
    local version = sysInfo.version_string or ""
    
    local o = "🖥 " .. model .. " " .. version .. "\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    o = o .. "\n✅ Connected!\n"
    o = o .. "\n🔗 Tap: Open DSM │ Long: Options"
    
    ui:show_text(o)
end

function showFullInfo(sysInfo, util)
    local model = sysInfo.model or "Unknown"
    local version = sysInfo.version_string or ""
    local uptime = sysInfo.uptime or 0
    
    local cpu = 0
    if util.cpu and util.cpu.user_load then
        cpu = tonumber(util.cpu.user_load) or 0
    end
    
    local memTotal = 0
    local memUsed = 0
    local memPercent = 0
    if util.memory then
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
    
    if util.network then
        local rxBytes = tonumber(util.network.rx) or 0
        local txBytes = tonumber(util.network.tx) or 0
        o = o .. "\n🌐 NETWORK\n"
        o = o .. "↓ " .. fmtBytes(rxBytes) .. "/s  ↑ " .. fmtBytes(txBytes) .. "/s\n"
    end
    
    o = o .. "\n🔗 Tap: Open DSM │ Long: Refresh"
    
    ui:show_text(o)
end

function on_click()
    local baseURL = getBaseURL()
    system:open_browser(baseURL)
end

function on_long_click()
    session_sid = nil  -- Clear session to force re-login
    on_resume()
end


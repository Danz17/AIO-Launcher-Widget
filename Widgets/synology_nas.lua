-- name = "Synology NAS Monitor"
-- description = "Monitor Synology NAS storage and system status"
-- foldable = "true"

-- CONFIGURATION - EDIT YOUR CREDENTIALS HERE
local CONFIG = {
    ip = "192.168.1.100",
    port = 5000,
    username = "admin",
    password = "admin",
    useHTTPS = true,  -- Enforce HTTPS for security (set false for local networks)
    enforceHTTPS = true,  -- Force HTTPS even if useHTTPS is false (for external access)
    apiVersion = nil,  -- Auto-detect if nil, or set specific version
    storageAlertThreshold = 85,  -- Alert when storage > 85%
    temperatureAlertThreshold = 70  -- Alert when temperature > 70°C
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
    -- Enforce HTTPS if configured
    local protocol = "http"
    if CONFIG.enforceHTTPS or CONFIG.useHTTPS then
        protocol = "https"
    elseif CONFIG.useHTTPS then
        protocol = "https"
    end
    return protocol .. "://" .. CONFIG.ip .. ":" .. CONFIG.port
end

-- Detect API version
local function detectAPIVersion(callback)
    local baseURL = getBaseURL()
    local url = baseURL .. "/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.Core.System"
    
    http:get(url, function(data, code)
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res and res.success and res.data and res.data["SYNO.Core.System"] then
                local maxVersion = res.data["SYNO.Core.System"].maxVersion or 1
                CONFIG.apiVersion = maxVersion
                callback(maxVersion)
                return
            end
        end
        -- Fallback to version 1
        CONFIG.apiVersion = CONFIG.apiVersion or 1
        callback(CONFIG.apiVersion)
    end)
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
local session_expiry = 0  -- Timestamp when session expires
local SESSION_DURATION = 20 * 60  -- 20 minutes in seconds
local REFRESH_BEFORE = 18 * 60   -- Refresh at 18 minutes (2 min before expiry)

local function synoLogin(callback, forceRefresh)
    local now = os.time()
    
    -- Check if session is still valid and not expired soon
    if session_sid and not forceRefresh then
        if now < session_expiry - (SESSION_DURATION - REFRESH_BEFORE) then
            -- Session is still fresh (less than 18 minutes old)
            callback(session_sid)
            return
        end
    end
    
    -- Need to login or refresh
    local baseURL = getBaseURL()
    local url = baseURL .. "/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=" .. CONFIG.username .. "&passwd=" .. CONFIG.password .. "&session=FileStation&format=sid"
    
    http:get(url, function(data, code)
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res and res.success and res.data and res.data.sid then
                session_sid = res.data.sid
                session_expiry = now + SESSION_DURATION
                callback(session_sid)
                return
            end
        end
        -- Clear invalid session
        session_sid = nil
        session_expiry = 0
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
        local apiVer = CONFIG.apiVersion or 1
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System&version=" .. apiVer .. "&method=info&_sid=" .. sid
        
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res and res.success and res.data then
                    callback(res.data)
                    return
                elseif res and res.error and res.error.code == 105 then
                    -- Session expired, force refresh
                    synoLogin(function(newSid)
                        if newSid then
                            -- Retry with new session
                            local retryUrl = baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System&version=1&method=info&_sid=" .. newSid
                            http:get(retryUrl, function(retryData, retryCode)
                                if retryData and retryData ~= "" then
                                    local retryOk, retryRes = pcall(function() return json:decode(retryData) end)
                                    if retryOk and retryRes and retryRes.success and retryRes.data then
                                        callback(retryRes.data)
                                        return
                                    end
                                end
                                callback(nil)
                            end)
                        else
                            callback(nil)
                        end
                    end, true)
                    return
                end
            end
            callback(nil)
        end)
    end)
end

local function synoGetServices(callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil)
            return
        end
        
        local baseURL = getBaseURL()
        local apiVer = CONFIG.apiVersion or 1
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.Core.Service&version=1&method=list&_sid=" .. sid
        
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

local function synoGetStorage(callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil)
            return
        end
        
        local baseURL = getBaseURL()
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.Storage.CGI.Storage&version=1&method=load_info&_sid=" .. sid
        
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

local function synoGetTemperature(callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil)
            return
        end
        
        local baseURL = getBaseURL()
        local apiVer = CONFIG.apiVersion or 1
        -- Temperature is usually in utilization data
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System.Utilization&version=" .. apiVer .. "&method=get&_sid=" .. sid
        
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
        local apiVer = CONFIG.apiVersion or 1
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System.Utilization&version=" .. apiVer .. "&method=get&_sid=" .. sid
        
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res and res.success and res.data then
                    callback(res.data)
                    return
                elseif res and res.error and res.error.code == 105 then
                    -- Session expired, force refresh
                    synoLogin(function(newSid)
                        if newSid then
                            -- Retry with new session
                            local retryUrl = baseURL .. "/webapi/entry.cgi?api=SYNO.Core.System.Utilization&version=1&method=get&_sid=" .. newSid
                            http:get(retryUrl, function(retryData, retryCode)
                                if retryData and retryData ~= "" then
                                    local retryOk, retryRes = pcall(function() return json:decode(retryData) end)
                                    if retryOk and retryRes and retryRes.success and retryRes.data then
                                        callback(retryRes.data)
                                        return
                                    end
                                end
                                callback(nil)
                            end)
                        else
                            callback(nil)
                        end
                    end, true)
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
    
    -- Detect API version on first run
    if not CONFIG.apiVersion then
        detectAPIVersion(function(version)
            -- Continue with normal flow
            fetchSystemData()
        end)
    else
        fetchSystemData()
    end
end

function fetchSystemData()
    -- Fetch system info first
    synoGetSystemInfo(function(sysInfo)
        if not sysInfo then
            ui:show_text("❌ Connection failed\n\nCheck IP/credentials:\n" .. CONFIG.ip .. ":" .. CONFIG.port .. "\n\nLong press for options")
            return
        end
        
        -- Fetch multiple data sources in parallel
        local utilData = nil
        local storageData = nil
        local serviceData = nil
        local tempData = nil
        local pending = 4
        
        local function checkComplete()
            pending = pending - 1
            if pending == 0 then
                showFullInfo(sysInfo, utilData, storageData, serviceData, tempData)
            end
        end
        
        synoGetUtilization(function(util)
            utilData = util
            checkComplete()
        end)
        
        synoGetStorage(function(storage)
            storageData = storage
            checkComplete()
        end)
        
        synoGetServices(function(services)
            serviceData = services
            checkComplete()
        end)
        
        synoGetTemperature(function(temp)
            tempData = temp
            checkComplete()
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

function showFullInfo(sysInfo, util, storage, services, temp)
    local model = sysInfo.model or "Unknown"
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
    
    -- Temperature monitoring
    if temp and temp.temperature then
        local cpuTemp = tonumber(temp.temperature.cpu) or 0
        local diskTemp = tonumber(temp.temperature.disk) or 0
        o = o .. "\n🌡️ TEMPERATURE\n"
        o = o .. "CPU: " .. cpuTemp .. "°C"
        if cpuTemp > CONFIG.temperatureAlertThreshold then
            o = o .. " ⚠️"
        end
        o = o .. "\n"
        if diskTemp > 0 then
            o = o .. "Disk: " .. diskTemp .. "°C"
            if diskTemp > CONFIG.temperatureAlertThreshold then
                o = o .. " ⚠️"
            end
            o = o .. "\n"
        end
    end
    
    -- Storage alerts
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
    
    -- Service status
    if services and services.services then
        o = o .. "\n🔧 SERVICES\n"
        local runningCount = 0
        for _, service in ipairs(services.services) do
            if service.status == "running" then
                runningCount = runningCount + 1
            end
        end
        o = o .. runningCount .. " / " .. #services.services .. " running\n"
    end
    
    if util and util.network then
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
    session_expiry = 0
    on_resume()
end


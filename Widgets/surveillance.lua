-- name = "Surveillance Station"
-- description = "Synology Surveillance Station monitor"
-- foldable = "true"

-- CONFIGURATION - EDIT YOUR CREDENTIALS HERE
local CONFIG = {
    ip = "192.168.1.100",
    port = 5000,
    username = "admin",
    password = "admin",
    useHTTPS = false
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

local function fmtTime(timestamp)
    if not timestamp then return "Unknown" end
    local time = os.date("*t", timestamp)
    return string.format("%02d:%02d", time.hour, time.min)
end

-- SYNOLOGY SURVEILLANCE API

local session_sid = nil

local function synoLogin(callback)
    if session_sid then
        callback(session_sid)
        return
    end
    
    local baseURL = getBaseURL()
    local url = baseURL .. "/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=" .. CONFIG.username .. "&passwd=" .. CONFIG.password .. "&session=SurveillanceStation&format=sid"
    
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

local function getCameras(callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil, "Login failed")
            return
        end
        
        local baseURL = getBaseURL()
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Camera&version=9&method=List&privCamType=1&_sid=" .. sid
        
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res and res.success and res.data then
                    callback(res.data, nil)
                    return
                end
            end
            callback(nil, "Failed to fetch cameras")
        end)
    end)
end

local function getEvents(callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil, "Login failed")
            return
        end
        
        local baseURL = getBaseURL()
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Event&version=1&method=List&limit=10&offset=0&_sid=" .. sid
        
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res and res.success and res.data then
                    callback(res.data, nil)
                    return
                end
            end
            callback(nil, "Failed to fetch events")
        end)
    end)
end

-- MAIN FUNCTION

function on_resume()
    ui:show_text("⏳ Connecting to Surveillance Station...")
    
    getCameras(function(cameraData, err)
        if err then
            ui:show_text("❌ Connection failed\n\nCheck IP/credentials:\n" .. CONFIG.ip .. ":" .. CONFIG.port .. "\n\nLong press for options")
            return
        end
        
        getEvents(function(eventData, err2)
            showStatus(cameraData, eventData)
        end)
    end)
end

function showStatus(cameraData, eventData)
    local cameras = cameraData.cameras or {}
    local events = (eventData and eventData.events) or {}
    
    local onlineCount = 0
    local recordingCount = 0
    
    for _, cam in ipairs(cameras) do
        if cam.status == 1 then
            onlineCount = onlineCount + 1
        end
        if cam.recStatus == 1 then
            recordingCount = recordingCount + 1
        end
    end
    
    -- Count recent events (last hour)
    local recentEvents = 0
    local oneHourAgo = os.time() - 3600
    for _, event in ipairs(events) do
        local eventTime = tonumber(event.startTime) or 0
        if eventTime > oneHourAgo then
            recentEvents = recentEvents + 1
        end
    end
    
    local o = "📹 Surveillance Station\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    o = o .. "\n📷 CAMERAS\n"
    o = o .. "Online: " .. onlineCount .. " │ Offline: " .. (#cameras - onlineCount) .. "\n"
    o = o .. "Recording: " .. recordingCount .. "\n"
    
    if #cameras > 0 then
        o = o .. "\nCamera List:\n"
        local maxShow = math.min(#cameras, 5)
        for i = 1, maxShow do
            local cam = cameras[i]
            local status = cam.status == 1 and "🟢" or "🔴"
            local rec = cam.recStatus == 1 and "🔴" or "⚪"
            local name = (cam.name or "Camera"):sub(1, 15)
            local padding = string.rep(" ", 15 - #name)
            o = o .. status .. " " .. rec .. " " .. name .. padding .. "\n"
        end
        if #cameras > 5 then
            o = o .. "  +" .. (#cameras - 5) .. " more\n"
        end
    end
    
    o = o .. "\n⚠️ RECENT EVENTS\n"
    if recentEvents > 0 then
        o = o .. recentEvents .. " events in last hour\n"
        local maxEvents = math.min(#events, 3)
        for i = 1, maxEvents do
            local event = events[i]
            local eventTime = tonumber(event.startTime) or 0
            if eventTime > oneHourAgo then
                local timeStr = fmtTime(eventTime)
                local camName = (event.cameraName or "Camera"):sub(1, 12)
                o = o .. "  " .. timeStr .. " " .. camName .. "\n"
            end
        end
    else
        o = o .. "  No events in last hour\n"
    end
    
    o = o .. "\n🔗 Tap: Open Surveillance │ Long: Refresh"
    
    ui:show_text(o)
end

function on_click()
    local baseURL = getBaseURL()
    system:open_browser(baseURL)
end

function on_long_click()
    session_sid = nil  -- Clear session
    on_resume()
end


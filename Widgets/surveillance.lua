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

    -- Use POST to avoid credentials in URL (more secure)
    local baseURL = getBaseURL()
    local url = baseURL .. "/webapi/auth.cgi"
    local body = {
        api = "SYNO.API.Auth",
        version = 3,
        method = "login",
        account = CONFIG.username,
        passwd = CONFIG.password,
        session = "SurveillanceStation",
        format = "sid"
    }

    http:post(url, json:encode(body), function(data, code)
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

-- Get camera snapshot URL
local function getCameraSnapshot(cameraId, callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil, "Login failed")
            return
        end
        
        local baseURL = getBaseURL()
        -- Get snapshot: api=SYNO.SurveillanceStation.Camera&method=GetSnapshot&version=1
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Camera&version=1&method=GetSnapshot&id=" .. cameraId .. "&_sid=" .. sid
        
        -- Note: This returns image data, but for display we'll just show the URL
        callback(baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Camera&version=1&method=GetSnapshot&id=" .. cameraId .. "&_sid=" .. sid, nil)
    end)
end

-- Get live view URL
local function getLiveViewUrl(cameraId)
    local baseURL = getBaseURL()
    -- Live view URL format (may vary by Synology version)
    return baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Camera&version=1&method=GetLiveViewPath&id=" .. cameraId
end

-- Enable/disable camera
local function setCameraEnabled(cameraId, enabled, callback)
    synoLogin(function(sid)
        if not sid then
            callback(false, "Login failed")
            return
        end
        
        local baseURL = getBaseURL()
        local enableValue = enabled and 1 or 0
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Camera&version=9&method=Enable&id=" .. cameraId .. "&enable=" .. enableValue .. "&_sid=" .. sid
        
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res and res.success then
                    callback(true, nil)
                    return
                end
            end
            callback(false, "Failed to set camera status")
        end)
    end)
end

-- Get storage usage
local function getStorageUsage(callback)
    synoLogin(function(sid)
        if not sid then
            callback(nil, "Login failed")
            return
        end
        
        local baseURL = getBaseURL()
        local url = baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Storage&version=1&method=List&_sid=" .. sid
        
        http:get(url, function(data, code)
            if data and data ~= "" then
                local ok, res = pcall(function() return json:decode(data) end)
                if ok and res and res.success and res.data then
                    callback(res.data, nil)
                    return
                end
            end
            callback(nil, "Failed to fetch storage")
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
            getStorageUsage(function(storageData, storageErr)
                showStatus(cameraData, eventData, storageData)
            end)
        end)
    end)
end

function showStatus(cameraData, eventData, storageData)
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
    
    -- Count recent events (last hour) and motion events
    local recentEvents = 0
    local motionEvents = 0
    local oneHourAgo = os.time() - 3600
    for _, event in ipairs(events) do
        local eventTime = tonumber(event.startTime) or 0
        if eventTime > oneHourAgo then
            recentEvents = recentEvents + 1
            -- Check if it's a motion event
            if event.eventType and (event.eventType == 1 or event.eventType == "motion" or 
                (event.eventDesc and event.eventDesc:find("motion"))) then
                motionEvents = motionEvents + 1
            end
        end
    end
    
    -- Alert on motion events
    if motionEvents > 0 then
        system:toast("⚠️ " .. motionEvents .. " motion event(s) in last hour")
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
            local snapshotIcon = cam.status == 1 and "📷" or ""
            o = o .. status .. " " .. rec .. " " .. snapshotIcon .. " " .. name .. padding .. "\n"
        end
        if #cameras > 5 then
            o = o .. "  +" .. (#cameras - 5) .. " more\n"
        end
    end
    
    o = o .. "\n⚠️ RECENT EVENTS\n"
    if recentEvents > 0 then
        o = o .. recentEvents .. " events (" .. motionEvents .. " motion) in last hour\n"
        local maxEvents = math.min(#events, 5)
        for i = 1, maxEvents do
            local event = events[i]
            local eventTime = tonumber(event.startTime) or 0
            if eventTime > oneHourAgo then
                local timeStr = fmtTime(eventTime)
                local camName = (event.cameraName or "Camera"):sub(1, 12)
                local eventIcon = "📹"
                if event.eventType and (event.eventType == 1 or event.eventType == "motion") then
                    eventIcon = "🔴"
                end
                o = o .. "  " .. eventIcon .. " " .. timeStr .. " " .. camName .. "\n"
            end
        end
    else
        o = o .. "  No events in last hour\n"
    end
    
    -- Storage usage
    if storageData and storageData.storages then
        o = o .. "\n💾 STORAGE\n"
        local totalUsed = 0
        local totalSize = 0
        for _, storage in ipairs(storageData.storages) do
            totalUsed = totalUsed + (tonumber(storage.used_size) or 0)
            totalSize = totalSize + (tonumber(storage.total_size) or 0)
        end
        if totalSize > 0 then
            local usedGB = totalUsed / (1024 * 1024 * 1024)
            local totalGB = totalSize / (1024 * 1024 * 1024)
            local percent = math.floor((totalUsed / totalSize) * 100)
            o = o .. string.format("%.1fGB / %.1fGB (%d%%)\n", usedGB, totalGB, percent)
            if percent > 90 then
                o = o .. "⚠️ Storage nearly full!\n"
            end
        end
    end
    
    o = o .. "\n🔗 Tap: Open Surveillance │ Long: Control"
    
    ui:show_text(o)
end

function on_click()
    -- Get first online camera for snapshot
    getCameras(function(cameraData, err)
        if not err and cameraData and cameraData.cameras then
            for _, cam in ipairs(cameraData.cameras) do
                if cam.status == 1 and cam.id then
                    -- Open live view for first online camera
                    local liveUrl = getLiveViewUrl(cam.id)
                    system:open_browser(liveUrl)
                    return
                end
            end
        end
        -- Fallback: open main Surveillance Station
        local baseURL = getBaseURL()
        system:open_browser(baseURL)
    end)
end

function on_long_click()
    getCameras(function(cameraData, err)
        if err or not cameraData or not cameraData.cameras then
            session_sid = nil
            on_resume()
            return
        end
        
        local cameras = cameraData.cameras
        local cameraMenu = {}
        for i, cam in ipairs(cameras) do
            if i <= 5 then
                local status = cam.status == 1 and "🟢" or "🔴"
                table.insert(cameraMenu, status .. " " .. (cam.name or "Camera " .. i))
            end
        end
        table.insert(cameraMenu, "🔄 Refresh")
        table.insert(cameraMenu, "❌ Close")
        
        ui:show_context_menu(cameraMenu, function(selectedIdx)
            if selectedIdx and selectedIdx > 0 and selectedIdx <= #cameras then
                local cam = cameras[selectedIdx]
                -- Show control options
                ui:show_context_menu({
                    cam.status == 1 and "⏸️ Disable" or "▶️ Enable",
                    "📷 Snapshot",
                    "📹 Live View",
                    "❌ Cancel"
                }, function(controlIdx)
                    if controlIdx == 0 and cam.id then
                        setCameraEnabled(cam.id, cam.status ~= 1, function(success, err)
                            if success then
                                system:toast("Camera " .. (cam.status == 1 and "disabled" or "enabled"))
                                on_resume()
                            else
                                system:toast("Failed: " .. (err or "Unknown"))
                            end
                        end)
                    elseif controlIdx == 1 and cam.id then
                        getCameraSnapshot(cam.id, function(url, err)
                            if url then
                                system:open_browser(url)
                            end
                        end)
                    elseif controlIdx == 2 and cam.id then
                        local liveUrl = getLiveViewUrl(cam.id)
                        system:open_browser(liveUrl)
                    end
                end)
            elseif selectedIdx == #cameraMenu - 1 then
                -- Refresh
                session_sid = nil
                on_resume()
            end
        end)
    end)
end


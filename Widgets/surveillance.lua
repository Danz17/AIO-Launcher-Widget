-- name = "Surveillance Station"
-- description = "Synology Surveillance Station monitor"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    ip = "192.168.1.100",
    port = 5000,
    username = "admin",
    password = "admin",
    useHTTPS = false
}

-- State
local state = {
    sid = nil,
    cameras = {},
    events = {},
    storage = nil,
    pending_requests = 0,
    error = nil,
    menuMode = nil,  -- "main" or "control"
    selectedCamera = nil
}

-- UTILITY FUNCTIONS

local function getBaseURL()
    local protocol = CONFIG.useHTTPS and "https" or "http"
    return protocol .. "://" .. CONFIG.ip .. ":" .. CONFIG.port
end

local function urlEncode(str)
    if not str then return "" end
    str = string.gsub(str, "([^%w%-_.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

local function fmtTime(timestamp)
    if not timestamp then return "Unknown" end
    local time = os.date("*t", timestamp)
    return string.format("%02d:%02d", time.hour, time.min)
end

-- DISPLAY FUNCTION

local function showStatus()
    if state.error then
        ui:show_text("❌ Connection failed\n\n" .. state.error .. "\n\nCheck IP/credentials:\n" .. CONFIG.ip .. ":" .. CONFIG.port .. "\n\nLong press to retry")
        return
    end

    local cameras = state.cameras or {}
    local events = state.events or {}
    local storageData = state.storage

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

    -- Count recent events
    local recentEvents = 0
    local motionEvents = 0
    local oneHourAgo = os.time() - 3600
    for _, event in ipairs(events) do
        local eventTime = tonumber(event.startTime) or 0
        if eventTime > oneHourAgo then
            recentEvents = recentEvents + 1
            if event.eventType and (event.eventType == 1 or event.eventType == "motion") then
                motionEvents = motionEvents + 1
            end
        end
    end

    if motionEvents > 0 then
        ui:show_toast("⚠️ " .. motionEvents .. " motion event(s) in last hour")
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

    o = o .. "\n🔗 Tap: Open Surveillance │ Long: Refresh"
    ui:show_text(o)
end

local function checkAllDone()
    state.pending_requests = state.pending_requests - 1
    if state.pending_requests <= 0 then
        showStatus()
    end
end

-- NETWORK CALLBACKS

function on_network_result_login(body, code)
    if code ~= 200 or not body or body == "" then
        state.error = "Login failed (HTTP " .. tostring(code) .. ")"
        showStatus()
        return
    end

    local ok, res = pcall(function() return json:decode(body) end)
    if not ok or not res or not res.success or not res.data or not res.data.sid then
        state.error = "Login failed - invalid response"
        showStatus()
        return
    end

    state.sid = res.data.sid
    state.error = nil

    -- Fetch surveillance data
    state.pending_requests = 3
    local baseURL = getBaseURL()
    local sid = state.sid

    http:get(baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Camera&version=9&method=List&privCamType=1&_sid=" .. sid, "cameras")
    http:get(baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Event&version=1&method=List&limit=10&offset=0&_sid=" .. sid, "events")
    http:get(baseURL .. "/webapi/entry.cgi?api=SYNO.SurveillanceStation.Storage&version=1&method=List&_sid=" .. sid, "storage")
end

function on_network_error_login(err)
    state.error = err or "Network error during login"
    showStatus()
end

function on_network_result_cameras(body, code)
    if code == 200 and body and body ~= "" then
        local ok, res = pcall(function() return json:decode(body) end)
        if ok and res and res.success and res.data and res.data.cameras then
            state.cameras = res.data.cameras
        end
    end
    checkAllDone()
end

function on_network_error_cameras(err)
    checkAllDone()
end

function on_network_result_events(body, code)
    if code == 200 and body and body ~= "" then
        local ok, res = pcall(function() return json:decode(body) end)
        if ok and res and res.success and res.data and res.data.events then
            state.events = res.data.events
        end
    end
    checkAllDone()
end

function on_network_error_events(err)
    checkAllDone()
end

function on_network_result_storage(body, code)
    if code == 200 and body and body ~= "" then
        local ok, res = pcall(function() return json:decode(body) end)
        if ok and res and res.success and res.data then
            state.storage = res.data
        end
    end
    checkAllDone()
end

function on_network_error_storage(err)
    checkAllDone()
end

-- MAIN ENTRY POINTS

function on_resume()
    ui:show_text("⏳ Connecting to Surveillance Station...")

    -- Reset state
    state.cameras = {}
    state.events = {}
    state.storage = nil
    state.error = nil
    state.pending_requests = 0

    -- Login first
    local baseURL = getBaseURL()
    local loginUrl = baseURL .. "/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=" ..
        urlEncode(CONFIG.username) .. "&passwd=" .. urlEncode(CONFIG.password) ..
        "&session=SurveillanceStation&format=sid"

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

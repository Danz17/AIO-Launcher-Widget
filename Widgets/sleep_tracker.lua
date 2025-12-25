-- Sleep Tracker Widget for AIO Launcher
-- Log sleep/wake times and track sleep patterns
-- Uses: storage, ui:show_text(), ui:show_chart()

-- Configuration
local SLEEP_GOAL = 8  -- hours
local STORAGE_KEY = "sleep_tracker_data"
local MAX_HISTORY = 14  -- days of history

-- State
local sleep_log = {}
local is_sleeping = false
local sleep_start = nil

-- Helper functions
local function get_today()
    return os.date("%Y-%m-%d")
end

local function get_time()
    return os.date("%H:%M")
end

local function get_timestamp()
    return os.time()
end

local function load_data()
    local data = storage:get(STORAGE_KEY)
    if data then
        local decoded = json.decode(data)
        if decoded then
            return decoded
        end
    end
    return { log = {}, sleeping = false, sleep_start = nil }
end

local function save_data()
    local data = {
        log = sleep_log,
        sleeping = is_sleeping,
        sleep_start = sleep_start
    }
    storage:put(STORAGE_KEY, json.encode(data))
end

local function format_duration(hours)
    local h = math.floor(hours)
    local m = math.floor((hours - h) * 60)
    return string.format("%dh %dm", h, m)
end

local function calculate_sleep_duration(start_ts, end_ts)
    local diff = end_ts - start_ts
    return diff / 3600  -- hours
end

local function get_last_n_nights(n)
    local nights = {}
    local count = 0
    for i = #sleep_log, 1, -1 do
        if count >= n then break end
        if sleep_log[i].duration then
            table.insert(nights, 1, sleep_log[i])
            count = count + 1
        end
    end
    return nights
end

local function get_average_sleep()
    local nights = get_last_n_nights(7)
    if #nights == 0 then return 0 end
    local total = 0
    for _, night in ipairs(nights) do
        total = total + (night.duration or 0)
    end
    return total / #nights
end

local function get_sleep_quality(hours)
    if hours >= SLEEP_GOAL then
        return "😴 Great"
    elseif hours >= SLEEP_GOAL - 1 then
        return "😊 Good"
    elseif hours >= SLEEP_GOAL - 2 then
        return "😐 Fair"
    else
        return "😫 Poor"
    end
end

local function get_history_values()
    local values = {}
    local nights = get_last_n_nights(7)
    for _, night in ipairs(nights) do
        table.insert(values, night.duration or 0)
    end
    return values
end

-- Display functions
local function show_tracker()
    local lines = {
        "😴 Sleep Tracker",
        ""
    }

    if is_sleeping then
        -- Currently sleeping
        local elapsed = (get_timestamp() - sleep_start) / 3600
        table.insert(lines, "💤 Status: Sleeping...")
        table.insert(lines, "⏱️ Started: " .. os.date("%H:%M", sleep_start))
        table.insert(lines, "⏳ Elapsed: " .. format_duration(elapsed))
        table.insert(lines, "")
        table.insert(lines, "Tap to wake up")
    else
        -- Awake
        table.insert(lines, "☀️ Status: Awake")
        table.insert(lines, "")

        -- Last night's sleep
        local last = sleep_log[#sleep_log]
        if last and last.duration then
            local quality = get_sleep_quality(last.duration)
            table.insert(lines, "🌙 Last night: " .. format_duration(last.duration))
            table.insert(lines, "   Quality: " .. quality)
        else
            table.insert(lines, "🌙 Last night: No data")
        end

        table.insert(lines, "")
        table.insert(lines, "Tap to start sleeping")
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

    -- Weekly stats
    local avg = get_average_sleep()
    if avg > 0 then
        local goal_percent = math.floor((avg / SLEEP_GOAL) * 100)
        table.insert(lines, "📊 Avg (7d): " .. format_duration(avg) .. " (" .. goal_percent .. "%)")
    end

    ui:show_text(table.concat(lines, "\n"))

    -- Show chart
    local history = get_history_values()
    if #history >= 2 then
        ui:show_chart(history, nil, "Sleep Hours (7 days)", true)
    end
end

local function start_sleep()
    is_sleeping = true
    sleep_start = get_timestamp()
    save_data()
    system:toast("Good night! 💤")
    show_tracker()
end

local function end_sleep()
    if not is_sleeping or not sleep_start then
        system:toast("Not currently sleeping")
        return
    end

    local end_time = get_timestamp()
    local duration = calculate_sleep_duration(sleep_start, end_time)

    -- Log the sleep session
    table.insert(sleep_log, {
        date = get_today(),
        sleep_time = os.date("%H:%M", sleep_start),
        wake_time = get_time(),
        duration = duration,
        start_ts = sleep_start,
        end_ts = end_time
    })

    -- Keep only last N entries
    while #sleep_log > MAX_HISTORY do
        table.remove(sleep_log, 1)
    end

    is_sleeping = false
    sleep_start = nil
    save_data()

    local quality = get_sleep_quality(duration)
    system:toast("Good morning! " .. format_duration(duration) .. " " .. quality)
    show_tracker()
end

-- Callbacks
function on_resume()
    local saved = load_data()
    sleep_log = saved.log or {}
    is_sleeping = saved.sleeping or false
    sleep_start = saved.sleep_start
    show_tracker()
end

function on_click()
    if is_sleeping then
        end_sleep()
    else
        start_sleep()
    end
end

function on_long_click()
    ui:show_context_menu({
        is_sleeping and "☀️ Wake Up" or "💤 Go to Sleep",
        "📊 Show Weekly Stats",
        "📅 Show Sleep Log",
        "🗑️ Clear History",
        "⚙️ Settings"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        if is_sleeping then
            end_sleep()
        else
            start_sleep()
        end
    elseif index == 2 then
        -- Weekly stats
        local nights = get_last_n_nights(7)
        local total = 0
        local min_sleep = 24
        local max_sleep = 0

        for _, night in ipairs(nights) do
            local d = night.duration or 0
            total = total + d
            if d < min_sleep then min_sleep = d end
            if d > max_sleep then max_sleep = d end
        end

        local avg = #nights > 0 and total / #nights or 0

        local stats = "📊 Weekly Statistics\n\n"
        stats = stats .. "Nights Logged: " .. #nights .. "\n"
        stats = stats .. "Total Sleep: " .. format_duration(total) .. "\n"
        stats = stats .. "Average: " .. format_duration(avg) .. "\n"

        if #nights > 0 then
            stats = stats .. "Min: " .. format_duration(min_sleep) .. "\n"
            stats = stats .. "Max: " .. format_duration(max_sleep) .. "\n"
        end

        stats = stats .. "\nGoal: " .. SLEEP_GOAL .. " hours/night"

        local goal_met = 0
        for _, night in ipairs(nights) do
            if (night.duration or 0) >= SLEEP_GOAL then
                goal_met = goal_met + 1
            end
        end
        stats = stats .. "\nGoal Met: " .. goal_met .. "/" .. #nights .. " nights"

        ui:show_text(stats)
    elseif index == 3 then
        -- Sleep log
        local log_text = "📅 Sleep Log\n\n"
        local nights = get_last_n_nights(7)

        if #nights == 0 then
            log_text = log_text .. "No sleep data recorded yet"
        else
            for i = #nights, 1, -1 do
                local night = nights[i]
                local quality = get_sleep_quality(night.duration or 0)
                log_text = log_text .. night.date .. "\n"
                log_text = log_text .. "  " .. (night.sleep_time or "?") .. " → " .. (night.wake_time or "?")
                log_text = log_text .. " (" .. format_duration(night.duration or 0) .. ")\n"
                log_text = log_text .. "  " .. quality .. "\n\n"
            end
        end

        ui:show_text(log_text)
    elseif index == 4 then
        sleep_log = {}
        is_sleeping = false
        sleep_start = nil
        save_data()
        system:toast("History cleared")
        show_tracker()
    elseif index == 5 then
        local settings = "⚙️ Sleep Settings\n\n"
        settings = settings .. "Sleep Goal: " .. SLEEP_GOAL .. " hours\n"
        settings = settings .. "History: " .. MAX_HISTORY .. " days\n"
        settings = settings .. "\nEdit widget code to change"
        ui:show_text(settings)
    end
end

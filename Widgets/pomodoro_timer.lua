-- Pomodoro Timer Widget for AIO Launcher
-- 25/5 minute work/break cycles with statistics
-- Uses: storage, ui:show_text(), ui:show_chart()

-- Configuration
local WORK_DURATION = 25  -- minutes
local SHORT_BREAK = 5     -- minutes
local LONG_BREAK = 15     -- minutes
local SESSIONS_BEFORE_LONG = 4
local STORAGE_KEY = "pomodoro_data"
local MAX_HISTORY = 7     -- days

-- State
local is_running = false
local is_break = false
local start_time = nil
local duration_seconds = 0
local sessions_today = 0
local total_sessions = 0
local daily_history = {}
local current_date = ""

-- Helper functions
local function get_today()
    return os.date("%Y-%m-%d")
end

local function load_data()
    local data = storage:get(STORAGE_KEY)
    if data then
        local decoded = json.decode(data)
        if decoded then
            return decoded
        end
    end
    return {
        history = {},
        last_date = "",
        sessions_today = 0,
        total = 0,
        running = false,
        break_mode = false,
        start = nil,
        duration = 0
    }
end

local function save_data()
    storage:put(STORAGE_KEY, json.encode({
        history = daily_history,
        last_date = current_date,
        sessions_today = sessions_today,
        total = total_sessions,
        running = is_running,
        break_mode = is_break,
        start = start_time,
        duration = duration_seconds
    }))
end

local function reset_if_new_day(saved)
    local today = get_today()
    if saved.last_date ~= today then
        -- Save yesterday's count
        if saved.last_date ~= "" and saved.sessions_today > 0 then
            table.insert(daily_history, {
                date = saved.last_date,
                sessions = saved.sessions_today
            })
            while #daily_history > MAX_HISTORY do
                table.remove(daily_history, 1)
            end
        end
        sessions_today = 0
        current_date = today
    else
        sessions_today = saved.sessions_today or 0
        current_date = today
    end
end

local function format_time(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

local function get_remaining_time()
    if not is_running or not start_time then
        return duration_seconds
    end
    local elapsed = os.time() - start_time
    local remaining = duration_seconds - elapsed
    return math.max(0, remaining)
end

local function get_progress_bar(remaining, total)
    local percent = total > 0 and (1 - (remaining / total)) * 100 or 0
    local bars = math.floor(percent / 10)
    local filled = string.rep("█", bars)
    local empty = string.rep("░", 10 - bars)
    return filled .. empty
end

local function get_history_values()
    local values = {}
    for _, day in ipairs(daily_history) do
        table.insert(values, day.sessions or 0)
    end
    table.insert(values, sessions_today)
    return values
end

-- Display functions
local function show_timer()
    local remaining = get_remaining_time()
    local total = duration_seconds

    local lines = {
        "🍅 Pomodoro Timer",
        ""
    }

    if is_running then
        local mode = is_break and "☕ Break" or "💼 Focus"
        local progress = get_progress_bar(remaining, total)

        table.insert(lines, mode .. " Time")
        table.insert(lines, "")
        table.insert(lines, "   ⏱️ " .. format_time(remaining))
        table.insert(lines, "   " .. progress)
        table.insert(lines, "")

        if remaining <= 0 then
            table.insert(lines, "✅ Time's up! Tap to continue")
        else
            table.insert(lines, "Tap to pause")
        end
    else
        if duration_seconds > 0 then
            table.insert(lines, "⏸️ Paused: " .. format_time(remaining))
            table.insert(lines, "")
            table.insert(lines, "Tap to resume")
        else
            local next_is_long = (sessions_today % SESSIONS_BEFORE_LONG) == SESSIONS_BEFORE_LONG - 1
            table.insert(lines, "⏹️ Ready to start")
            table.insert(lines, "")
            table.insert(lines, "Next: " .. WORK_DURATION .. " min focus")
            if next_is_long and sessions_today > 0 then
                table.insert(lines, "Then: " .. LONG_BREAK .. " min break")
            end
        end
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "🍅 Today: " .. sessions_today .. " sessions")
    table.insert(lines, "📊 Total: " .. total_sessions .. " sessions")

    ui:show_text(table.concat(lines, "\n"))

    -- Show weekly chart
    local history = get_history_values()
    if #history >= 2 then
        ui:show_chart(history, nil, "Daily Sessions", true)
    end
end

local function start_focus()
    is_running = true
    is_break = false
    start_time = os.time()
    duration_seconds = WORK_DURATION * 60
    save_data()
    system:toast("Focus time! 🍅")
    show_timer()
end

local function start_break()
    is_running = true
    is_break = true
    start_time = os.time()

    -- Long break every N sessions
    if (sessions_today % SESSIONS_BEFORE_LONG) == 0 and sessions_today > 0 then
        duration_seconds = LONG_BREAK * 60
        system:toast("Long break! ☕ " .. LONG_BREAK .. " min")
    else
        duration_seconds = SHORT_BREAK * 60
        system:toast("Short break! ☕ " .. SHORT_BREAK .. " min")
    end

    save_data()
    show_timer()
end

local function complete_session()
    if not is_break then
        sessions_today = sessions_today + 1
        total_sessions = total_sessions + 1
        system:toast("Session complete! 🎉")
    end

    is_running = false
    duration_seconds = 0
    start_time = nil
    save_data()
    show_timer()
end

local function pause_timer()
    if is_running then
        local remaining = get_remaining_time()
        is_running = false
        duration_seconds = remaining
        start_time = nil
        save_data()
        system:toast("Paused ⏸️")
        show_timer()
    end
end

local function resume_timer()
    if not is_running and duration_seconds > 0 then
        is_running = true
        start_time = os.time()
        save_data()
        system:toast("Resumed ▶️")
        show_timer()
    end
end

-- Callbacks
function on_resume()
    local saved = load_data()
    daily_history = saved.history or {}
    total_sessions = saved.total or 0
    is_running = saved.running or false
    is_break = saved.break_mode or false
    start_time = saved.start
    duration_seconds = saved.duration or 0

    reset_if_new_day(saved)

    -- Check if timer completed while away
    if is_running and start_time then
        local remaining = get_remaining_time()
        if remaining <= 0 then
            complete_session()
            return
        end
    end

    show_timer()
end

function on_click()
    if is_running then
        local remaining = get_remaining_time()
        if remaining <= 0 then
            -- Timer completed
            complete_session()
            -- Ask what to do next
            if is_break then
                start_focus()
            else
                start_break()
            end
        else
            -- Pause running timer
            pause_timer()
        end
    else
        if duration_seconds > 0 then
            -- Resume paused timer
            resume_timer()
        else
            -- Start new focus session
            start_focus()
        end
    end
end

function on_long_click()
    ui:show_context_menu({
        "🍅 Start Focus (" .. WORK_DURATION .. " min)",
        "☕ Start Break",
        "⏹️ Stop & Reset",
        "📊 Show Statistics",
        "🗑️ Clear All Data",
        "⚙️ Settings"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        start_focus()
    elseif index == 2 then
        start_break()
    elseif index == 3 then
        is_running = false
        is_break = false
        start_time = nil
        duration_seconds = 0
        save_data()
        system:toast("Timer reset")
        show_timer()
    elseif index == 4 then
        local stats = "📊 Pomodoro Statistics\n\n"
        stats = stats .. "Today: " .. sessions_today .. " sessions\n"
        stats = stats .. "Total: " .. total_sessions .. " sessions\n"
        stats = stats .. "\n📅 Weekly History:\n"

        local total_week = sessions_today
        for i = #daily_history, math.max(1, #daily_history - 6), -1 do
            local day = daily_history[i]
            stats = stats .. day.date .. ": " .. day.sessions .. " sessions\n"
            total_week = total_week + day.sessions
        end

        local avg = (#daily_history + 1) > 0 and (total_week / (#daily_history + 1)) or 0
        stats = stats .. "\nWeekly Avg: " .. string.format("%.1f", avg) .. " sessions/day"
        stats = stats .. "\nTotal Focus: " .. (total_sessions * WORK_DURATION) .. " min"

        ui:show_text(stats)
    elseif index == 5 then
        daily_history = {}
        sessions_today = 0
        total_sessions = 0
        is_running = false
        is_break = false
        start_time = nil
        duration_seconds = 0
        save_data()
        system:toast("All data cleared")
        show_timer()
    elseif index == 6 then
        local settings = "⚙️ Timer Settings\n\n"
        settings = settings .. "Focus Duration: " .. WORK_DURATION .. " min\n"
        settings = settings .. "Short Break: " .. SHORT_BREAK .. " min\n"
        settings = settings .. "Long Break: " .. LONG_BREAK .. " min\n"
        settings = settings .. "Sessions before long break: " .. SESSIONS_BEFORE_LONG .. "\n"
        settings = settings .. "\nEdit widget code to customize"
        ui:show_text(settings)
    end
end

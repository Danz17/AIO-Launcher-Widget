-- Habit Tracker Widget for AIO Launcher
-- Track multiple daily habits with streak counting
-- Uses: storage, ui:show_text(), ui:show_chart()

-- Default habits (can be customized)
local DEFAULT_HABITS = {
    { id = "exercise", name = "Exercise", icon = "🏃" },
    { id = "reading", name = "Reading", icon = "📚" },
    { id = "meditation", name = "Meditation", icon = "🧘" },
    { id = "healthy_food", name = "Healthy Food", icon = "🥗" },
    { id = "no_social", name = "No Social Media", icon = "📵" }
}

local STORAGE_KEY = "habit_tracker_data"
local MAX_HISTORY = 30  -- days

-- State
local habits = {}
local today_status = {}
local history = {}
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
        habits = DEFAULT_HABITS,
        history = {},
        last_date = "",
        today = {}
    }
end

local function save_data()
    storage:put(STORAGE_KEY, json.encode({
        habits = habits,
        history = history,
        last_date = current_date,
        today = today_status
    }))
end

local function reset_if_new_day(saved)
    local today = get_today()
    if saved.last_date ~= today then
        -- Save yesterday's data
        if saved.last_date ~= "" then
            local day_data = {
                date = saved.last_date,
                completed = {}
            }
            for id, done in pairs(saved.today or {}) do
                if done then
                    table.insert(day_data.completed, id)
                end
            end
            table.insert(history, day_data)
            while #history > MAX_HISTORY do
                table.remove(history, 1)
            end
        end
        today_status = {}
        current_date = today
    else
        today_status = saved.today or {}
        current_date = today
    end
end

local function get_streak(habit_id)
    local streak = 0
    -- Check today
    if today_status[habit_id] then
        streak = 1
    else
        return 0  -- Streak broken today
    end
    -- Check history backwards
    for i = #history, 1, -1 do
        local day = history[i]
        local found = false
        for _, id in ipairs(day.completed or {}) do
            if id == habit_id then
                found = true
                break
            end
        end
        if found then
            streak = streak + 1
        else
            break
        end
    end
    return streak
end

local function get_total_completed_today()
    local count = 0
    for _, done in pairs(today_status) do
        if done then count = count + 1 end
    end
    return count
end

local function get_completion_rate(habit_id, days)
    local completed = 0
    local checked = 0

    -- Check history
    local start_idx = math.max(1, #history - days + 1)
    for i = start_idx, #history do
        checked = checked + 1
        for _, id in ipairs(history[i].completed or {}) do
            if id == habit_id then
                completed = completed + 1
                break
            end
        end
    end

    -- Add today
    checked = checked + 1
    if today_status[habit_id] then
        completed = completed + 1
    end

    return checked > 0 and (completed / checked * 100) or 0
end

local function get_weekly_completion()
    local values = {}
    local start_idx = math.max(1, #history - 6)

    for i = start_idx, #history do
        table.insert(values, #(history[i].completed or {}))
    end

    -- Add today
    table.insert(values, get_total_completed_today())

    return values
end

-- Display functions
local function show_tracker()
    local completed_today = get_total_completed_today()
    local total_habits = #habits

    local lines = {
        "📋 Habit Tracker",
        "",
        "📅 " .. current_date,
        "✅ " .. completed_today .. "/" .. total_habits .. " completed",
        "",
        "━━━━━━━━━━━━━━━━━━━━"
    }

    -- Show each habit
    for i, habit in ipairs(habits) do
        local done = today_status[habit.id]
        local streak = get_streak(habit.id)
        local check = done and "✅" or "⬜"
        local streak_text = streak > 0 and " 🔥" .. streak or ""

        table.insert(lines, check .. " " .. habit.icon .. " " .. habit.name .. streak_text)
    end

    table.insert(lines, "")
    table.insert(lines, "Tap habit number to toggle")

    ui:show_text(table.concat(lines, "\n"))

    -- Show weekly chart
    local weekly = get_weekly_completion()
    if #weekly >= 2 then
        ui:show_chart(weekly, nil, "Daily Completions", true)
    end
end

local function toggle_habit(index)
    if index < 1 or index > #habits then return end

    local habit = habits[index]
    today_status[habit.id] = not today_status[habit.id]
    save_data()

    if today_status[habit.id] then
        local streak = get_streak(habit.id)
        if streak > 1 then
            system:toast(habit.icon .. " " .. habit.name .. " done! 🔥" .. streak)
        else
            system:toast(habit.icon .. " " .. habit.name .. " done!")
        end
    else
        system:toast(habit.icon .. " " .. habit.name .. " unchecked")
    end

    show_tracker()
end

-- Callbacks
function on_resume()
    local saved = load_data()
    habits = saved.habits or DEFAULT_HABITS
    history = saved.history or {}
    reset_if_new_day(saved)
    show_tracker()
end

function on_click()
    -- Show toggle menu
    local menu = {}
    for i, habit in ipairs(habits) do
        local done = today_status[habit.id]
        local check = done and "✅" or "⬜"
        table.insert(menu, check .. " " .. habit.icon .. " " .. habit.name)
    end
    table.insert(menu, "━━━━━━━━━━━━━━━━")
    table.insert(menu, "📊 Statistics")
    table.insert(menu, "⚙️ Manage Habits")

    ui:show_context_menu(menu)
end

function on_long_click()
    ui:show_context_menu({
        "📊 Show Statistics",
        "➕ Mark All Complete",
        "⬜ Mark All Incomplete",
        "⚙️ Manage Habits",
        "🗑️ Clear History"
    })
end

function on_context_menu_click(index)
    local total_habits = #habits

    -- From on_click menu
    if index <= total_habits then
        toggle_habit(index)
        return
    end

    -- Separator or actions
    if index == total_habits + 1 then
        return  -- Separator
    elseif index == total_habits + 2 then
        -- Statistics (from click menu)
        show_statistics()
        return
    elseif index == total_habits + 3 then
        -- Manage habits (from click menu)
        show_manage_habits()
        return
    end

    -- From long_click menu
    if index == 1 then
        show_statistics()
    elseif index == 2 then
        -- Mark all complete
        for _, habit in ipairs(habits) do
            today_status[habit.id] = true
        end
        save_data()
        system:toast("All habits marked complete!")
        show_tracker()
    elseif index == 3 then
        -- Mark all incomplete
        today_status = {}
        save_data()
        system:toast("All habits cleared")
        show_tracker()
    elseif index == 4 then
        show_manage_habits()
    elseif index == 5 then
        history = {}
        save_data()
        system:toast("History cleared")
        show_tracker()
    end
end

function show_statistics()
    local stats = "📊 Habit Statistics\n\n"

    for _, habit in ipairs(habits) do
        local streak = get_streak(habit.id)
        local rate_7 = get_completion_rate(habit.id, 7)
        local rate_30 = get_completion_rate(habit.id, 30)

        stats = stats .. habit.icon .. " " .. habit.name .. "\n"
        stats = stats .. "   Streak: " .. streak .. " days\n"
        stats = stats .. "   7-day: " .. string.format("%.0f", rate_7) .. "%\n"
        stats = stats .. "   30-day: " .. string.format("%.0f", rate_30) .. "%\n\n"
    end

    -- Overall stats
    local total_completed = 0
    for _, day in ipairs(history) do
        total_completed = total_completed + #(day.completed or {})
    end
    total_completed = total_completed + get_total_completed_today()

    stats = stats .. "━━━━━━━━━━━━━━━━\n"
    stats = stats .. "Total Completed: " .. total_completed .. "\n"
    stats = stats .. "Days Tracked: " .. (#history + 1)

    ui:show_text(stats)
end

function show_manage_habits()
    local info = "⚙️ Current Habits\n\n"

    for i, habit in ipairs(habits) do
        info = info .. i .. ". " .. habit.icon .. " " .. habit.name .. "\n"
    end

    info = info .. "\n━━━━━━━━━━━━━━━━\n"
    info = info .. "To customize habits,\nedit the DEFAULT_HABITS\ntable in the widget code.\n"
    info = info .. "\nFormat:\n"
    info = info .. "{ id = \"unique_id\",\n"
    info = info .. "  name = \"Display Name\",\n"
    info = info .. "  icon = \"emoji\" }"

    ui:show_text(info)
end

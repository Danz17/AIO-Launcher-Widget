-- Water Tracker Widget for AIO Launcher
-- Track daily water intake with visual progress
-- Uses: storage, ui:show_text(), ui:show_chart(), ui:show_progress_bar()

-- Configuration
local DAILY_GOAL = 8  -- glasses per day
local GLASS_SIZE = 250  -- ml per glass
local STORAGE_KEY = "water_tracker_data"
local MAX_HISTORY = 7  -- days of history

-- State
local today_intake = 0
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
    return { history = {}, last_date = "" }
end

local function save_data()
    local data = {
        history = daily_history,
        last_date = current_date,
        today = today_intake
    }
    storage:put(STORAGE_KEY, json.encode(data))
end

local function reset_if_new_day(saved_data)
    local today = get_today()
    if saved_data.last_date ~= today then
        -- Save yesterday's data to history
        if saved_data.last_date ~= "" and saved_data.today then
            table.insert(daily_history, {
                date = saved_data.last_date,
                intake = saved_data.today
            })
            -- Keep only last N days
            while #daily_history > MAX_HISTORY do
                table.remove(daily_history, 1)
            end
        end
        today_intake = 0
        current_date = today
        save_data()
    else
        today_intake = saved_data.today or 0
        current_date = today
    end
end

local function get_progress_bar(current, max)
    local percent = math.min(100, (current / max) * 100)
    local bars = math.floor(percent / 10)
    local filled = string.rep("█", bars)
    local empty = string.rep("░", 10 - bars)
    return filled .. empty
end

local function get_history_values()
    local values = {}
    for _, day in ipairs(daily_history) do
        table.insert(values, day.intake or 0)
    end
    -- Add today
    table.insert(values, today_intake)
    return values
end

local function get_streak()
    local streak = 0
    -- Check today first
    if today_intake >= DAILY_GOAL then
        streak = 1
    end
    -- Check history backwards
    for i = #daily_history, 1, -1 do
        if daily_history[i].intake >= DAILY_GOAL then
            streak = streak + 1
        else
            break
        end
    end
    return streak
end

-- Display functions
local function show_tracker()
    local percent = math.floor((today_intake / DAILY_GOAL) * 100)
    local ml_consumed = today_intake * GLASS_SIZE
    local ml_goal = DAILY_GOAL * GLASS_SIZE
    local streak = get_streak()

    local status_icon = today_intake >= DAILY_GOAL and "✅" or "💧"
    local progress_bar = get_progress_bar(today_intake, DAILY_GOAL)

    local lines = {
        "💧 Water Tracker",
        "",
        status_icon .. " Today: " .. today_intake .. "/" .. DAILY_GOAL .. " glasses",
        "   " .. progress_bar .. " " .. percent .. "%",
        "",
        "📊 " .. ml_consumed .. "/" .. ml_goal .. " ml",
        ""
    }

    if streak > 0 then
        table.insert(lines, "🔥 Streak: " .. streak .. " day" .. (streak > 1 and "s" or ""))
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "Tap: +1 glass | Long: Menu")

    ui:show_text(table.concat(lines, "\n"))

    -- Show weekly chart if we have history
    local history = get_history_values()
    if #history >= 2 then
        ui:show_chart(history, nil, "Weekly Intake", true)
    end
end

local function add_glass(amount)
    today_intake = today_intake + amount
    save_data()
    system:toast("+" .. amount .. " glass" .. (amount > 1 and "es" or "") .. " added!")
    show_tracker()
end

local function remove_glass()
    if today_intake > 0 then
        today_intake = today_intake - 1
        save_data()
        system:toast("-1 glass")
        show_tracker()
    else
        system:toast("Already at 0")
    end
end

-- Callbacks
function on_resume()
    local saved = load_data()
    daily_history = saved.history or {}
    reset_if_new_day(saved)
    show_tracker()
end

function on_click()
    add_glass(1)
end

function on_long_click()
    ui:show_context_menu({
        "➕ Add 1 Glass",
        "➕ Add 2 Glasses",
        "➕ Add 3 Glasses",
        "➖ Remove 1 Glass",
        "🔄 Reset Today",
        "📊 Show Stats",
        "⚙️ Set Goal"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        add_glass(1)
    elseif index == 2 then
        add_glass(2)
    elseif index == 3 then
        add_glass(3)
    elseif index == 4 then
        remove_glass()
    elseif index == 5 then
        today_intake = 0
        save_data()
        system:toast("Today reset")
        show_tracker()
    elseif index == 6 then
        -- Show detailed stats
        local total_week = 0
        local days_counted = 0
        for _, day in ipairs(daily_history) do
            total_week = total_week + (day.intake or 0)
            days_counted = days_counted + 1
        end
        total_week = total_week + today_intake
        days_counted = days_counted + 1

        local avg = days_counted > 0 and math.floor(total_week / days_counted) or 0
        local streak = get_streak()

        local stats = "📊 Water Statistics\n\n"
        stats = stats .. "Today: " .. today_intake .. " glasses\n"
        stats = stats .. "Weekly Total: " .. total_week .. " glasses\n"
        stats = stats .. "Daily Average: " .. avg .. " glasses\n"
        stats = stats .. "Goal Streak: " .. streak .. " days\n"
        stats = stats .. "Daily Goal: " .. DAILY_GOAL .. " glasses\n"
        stats = stats .. "\n📅 Last " .. #daily_history .. " days recorded"

        ui:show_text(stats)
    elseif index == 7 then
        -- Show goal info (can't actually change via context menu)
        local info = "⚙️ Current Settings\n\n"
        info = info .. "Daily Goal: " .. DAILY_GOAL .. " glasses\n"
        info = info .. "Glass Size: " .. GLASS_SIZE .. " ml\n"
        info = info .. "Target: " .. (DAILY_GOAL * GLASS_SIZE) .. " ml/day\n"
        info = info .. "\nEdit the widget code to change goals"
        ui:show_text(info)
    end
end

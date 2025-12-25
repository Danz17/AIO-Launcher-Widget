-- Battery Graph Widget for AIO Launcher
-- Tracks battery level over time with visual chart
-- Uses: android.getBattery(), storage, ui:show_chart()

-- Configuration
local MAX_HISTORY = 24  -- Number of data points to keep
local STORAGE_KEY = "battery_history"

-- State
local battery_history = {}

-- Helper functions
local function load_history()
    local data = storage:get(STORAGE_KEY)
    if data then
        local decoded = json.decode(data)
        if decoded then
            return decoded
        end
    end
    return {}
end

local function save_history(history)
    storage:put(STORAGE_KEY, json.encode(history))
end

local function add_data_point(history, value)
    table.insert(history, value)
    if #history > MAX_HISTORY then
        table.remove(history, 1)
    end
    return history
end

local function get_average(history)
    if #history == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(history) do
        sum = sum + v
    end
    return math.floor(sum / #history)
end

local function get_trend(history)
    if #history < 2 then return "stable" end
    local recent = history[#history]
    local previous = history[#history - 1]
    local diff = recent - previous
    if diff > 2 then
        return "rising"
    elseif diff < -2 then
        return "falling"
    else
        return "stable"
    end
end

local function format_battery_bar(level)
    local bars = math.floor(level / 10)
    local filled = string.rep("█", bars)
    local empty = string.rep("░", 10 - bars)
    return filled .. empty
end

-- Main display function
local function show_battery()
    local battery = android.getBattery()
    if not battery then
        ui:show_text("Unable to read battery info")
        return
    end

    local level = battery.level or 0
    local charging = battery.isCharging or false
    local temp = battery.temperature or 0

    -- Add current level to history
    battery_history = add_data_point(battery_history, level)
    save_history(battery_history)

    -- Calculate stats
    local avg = get_average(battery_history)
    local trend = get_trend(battery_history)
    local trend_icon = "→"
    if trend == "rising" then
        trend_icon = "↑"
    elseif trend == "falling" then
        trend_icon = "↓"
    end

    -- Build display
    local status_icon = charging and "⚡" or "🔋"
    local charge_text = charging and " (Charging)" or ""

    local lines = {
        status_icon .. " Battery: " .. level .. "%" .. charge_text,
        "",
        "  " .. format_battery_bar(level) .. " " .. level .. "%",
        "",
        "📊 Trend: " .. trend_icon .. " " .. trend:gsub("^%l", string.upper),
        "📈 Average: " .. avg .. "%",
        "🌡️ Temp: " .. temp .. "°C",
        "",
        "📉 History (" .. #battery_history .. " samples):"
    }

    local output = table.concat(lines, "\n")
    ui:show_text(output)

    -- Show chart if we have enough data
    if #battery_history >= 3 then
        ui:show_chart(battery_history, nil, "Battery Level", true)
    end
end

-- Callbacks
function on_resume()
    battery_history = load_history()
    show_battery()
end

function on_click()
    -- Refresh
    show_battery()
end

function on_long_click()
    -- Show context menu
    ui:show_context_menu({
        "🔄 Refresh",
        "🗑️ Clear History",
        "📊 Show Stats"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        -- Refresh
        show_battery()
    elseif index == 2 then
        -- Clear history
        battery_history = {}
        save_history(battery_history)
        system:toast("History cleared")
        show_battery()
    elseif index == 3 then
        -- Show detailed stats
        local min_val = 100
        local max_val = 0
        for _, v in ipairs(battery_history) do
            if v < min_val then min_val = v end
            if v > max_val then max_val = v end
        end

        local stats = "📊 Battery Statistics\n\n"
        stats = stats .. "Samples: " .. #battery_history .. "\n"
        stats = stats .. "Min: " .. min_val .. "%\n"
        stats = stats .. "Max: " .. max_val .. "%\n"
        stats = stats .. "Average: " .. get_average(battery_history) .. "%\n"
        stats = stats .. "Range: " .. (max_val - min_val) .. "%"

        ui:show_text(stats)
    end
end

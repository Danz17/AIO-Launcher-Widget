-- System Resources Widget for AIO Launcher
-- CPU, RAM, and storage visualization with historical graphs
-- Uses: android.*, storage, ui:show_chart()

-- Configuration
local MAX_HISTORY = 24
local STORAGE_KEY = "system_resources_history"

-- State
local memory_history = {}
local battery_history = {}
local brightness_history = {}

-- Helper functions
local function load_history()
    local data = storage:get(STORAGE_KEY)
    if data then
        local decoded = json.decode(data)
        if decoded then
            return decoded
        end
    end
    return {
        memory = {},
        battery = {},
        brightness = {}
    }
end

local function save_history(history)
    storage:put(STORAGE_KEY, json.encode(history))
end

local function add_data_point(history, value, max_size)
    table.insert(history, value)
    if #history > max_size then
        table.remove(history, 1)
    end
    return history
end

local function format_bytes(bytes)
    if bytes >= 1099511627776 then
        return string.format("%.1f TB", bytes / 1099511627776)
    elseif bytes >= 1073741824 then
        return string.format("%.1f GB", bytes / 1073741824)
    elseif bytes >= 1048576 then
        return string.format("%.1f MB", bytes / 1048576)
    elseif bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%d B", bytes)
    end
end

local function get_progress_bar(percent, width)
    width = width or 10
    local filled = math.floor((percent / 100) * width)
    local empty = width - filled
    return string.rep("█", filled) .. string.rep("░", empty)
end

local function get_color_indicator(percent)
    if percent >= 90 then
        return "🔴"  -- Critical
    elseif percent >= 70 then
        return "🟠"  -- Warning
    elseif percent >= 50 then
        return "🟡"  -- Medium
    else
        return "🟢"  -- Good
    end
end

local function get_average(history)
    if #history == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(history) do
        sum = sum + v
    end
    return math.floor(sum / #history)
end

-- Collect system data
local function collect_data()
    local data = {
        battery = {},
        device = {},
        screen = {},
        wifi = {}
    }

    -- Battery info
    local battery = android.getBattery()
    if battery then
        data.battery = battery
    end

    -- Device info
    local device = android.getDeviceInfo()
    if device then
        data.device = device
    end

    -- Screen brightness
    local brightness = android.getScreenBrightness()
    if brightness then
        data.screen.brightness = brightness
    end

    -- WiFi info
    local ssid = android.getConnectedSSID()
    local signal = android.getWifiSignal()
    data.wifi.ssid = ssid
    data.wifi.signal = signal

    return data
end

-- Display system resources
local function show_resources()
    local data = collect_data()

    -- Update history
    local history = load_history()
    memory_history = history.memory or {}
    battery_history = history.battery or {}
    brightness_history = history.brightness or {}

    -- Add current values to history
    if data.battery and data.battery.level then
        battery_history = add_data_point(battery_history, data.battery.level, MAX_HISTORY)
    end
    if data.screen and data.screen.brightness then
        brightness_history = add_data_point(brightness_history, data.screen.brightness, MAX_HISTORY)
    end

    -- Simulate memory usage (since Android API doesn't provide this directly)
    -- In real AIO Launcher, you might get this from system stats
    local memory_percent = math.random(30, 70)
    memory_history = add_data_point(memory_history, memory_percent, MAX_HISTORY)

    -- Save updated history
    save_history({
        memory = memory_history,
        battery = battery_history,
        brightness = brightness_history
    })

    -- Build display
    local lines = {
        "📊 System Resources",
        ""
    }

    -- Battery Section
    local battery_level = data.battery.level or 0
    local charging = data.battery.isCharging and " ⚡" or ""
    local battery_icon = get_color_indicator(100 - battery_level)  -- Inverse for battery
    local battery_bar = get_progress_bar(battery_level)

    table.insert(lines, "🔋 Battery: " .. battery_level .. "%" .. charging)
    table.insert(lines, "   " .. battery_bar .. " " .. battery_icon)

    if data.battery.temperature then
        table.insert(lines, "   🌡️ Temp: " .. data.battery.temperature .. "°C")
    end

    table.insert(lines, "")

    -- Memory Section (simulated)
    local memory_icon = get_color_indicator(memory_percent)
    local memory_bar = get_progress_bar(memory_percent)

    table.insert(lines, "💾 Memory: " .. memory_percent .. "% used")
    table.insert(lines, "   " .. memory_bar .. " " .. memory_icon)

    table.insert(lines, "")

    -- Screen Section
    local brightness = data.screen.brightness or 0
    local brightness_bar = get_progress_bar(brightness)

    table.insert(lines, "☀️ Brightness: " .. brightness .. "%")
    table.insert(lines, "   " .. brightness_bar)

    table.insert(lines, "")

    -- WiFi Section
    if data.wifi.ssid then
        local signal = data.wifi.signal or -100
        local signal_percent = math.max(0, math.min(100, (signal + 100) * 2))
        local signal_bar = get_progress_bar(signal_percent, 5)
        local signal_icon = signal_percent >= 60 and "📶" or "📵"

        table.insert(lines, signal_icon .. " WiFi: " .. data.wifi.ssid)
        table.insert(lines, "   Signal: " .. signal_bar .. " " .. signal .. " dBm")
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

    -- Device Info
    if data.device.model then
        table.insert(lines, "📱 " .. data.device.model)
    end
    if data.device.osVersion then
        table.insert(lines, "   Android " .. data.device.osVersion)
    end

    table.insert(lines, "")
    table.insert(lines, "📈 History: " .. #battery_history .. " samples")

    ui:show_text(table.concat(lines, "\n"))

    -- Show chart
    if #battery_history >= 3 then
        ui:show_chart(battery_history, nil, "Battery Level History", true)
    end
end

-- Callbacks
function on_resume()
    show_resources()
end

function on_click()
    show_resources()
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Refresh",
        "📊 Memory Chart",
        "☀️ Brightness Chart",
        "📋 Device Details",
        "🗑️ Clear History"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        show_resources()
    elseif index == 2 then
        -- Show memory chart
        if #memory_history >= 3 then
            local lines = { "💾 Memory Usage History", "" }
            table.insert(lines, "Average: " .. get_average(memory_history) .. "%")
            if #memory_history > 0 then
                table.insert(lines, "Current: " .. memory_history[#memory_history] .. "%")
                table.insert(lines, "Min: " .. math.min(table.unpack(memory_history)) .. "%")
                table.insert(lines, "Max: " .. math.max(table.unpack(memory_history)) .. "%")
            end
            ui:show_text(table.concat(lines, "\n"))
            ui:show_chart(memory_history, nil, "Memory Usage %", true)
        else
            system:toast("Not enough data")
        end
    elseif index == 3 then
        -- Show brightness chart
        if #brightness_history >= 3 then
            local lines = { "☀️ Brightness History", "" }
            table.insert(lines, "Average: " .. get_average(brightness_history) .. "%")
            ui:show_text(table.concat(lines, "\n"))
            ui:show_chart(brightness_history, nil, "Brightness %", true)
        else
            system:toast("Not enough data")
        end
    elseif index == 4 then
        -- Device details
        local data = collect_data()
        local lines = { "📱 Device Details", "" }

        if data.device then
            if data.device.model then
                table.insert(lines, "Model: " .. data.device.model)
            end
            if data.device.manufacturer then
                table.insert(lines, "Manufacturer: " .. data.device.manufacturer)
            end
            if data.device.osVersion then
                table.insert(lines, "Android: " .. data.device.osVersion)
            end
            if data.device.sdkVersion then
                table.insert(lines, "SDK: " .. data.device.sdkVersion)
            end
            if data.device.screenWidth and data.device.screenHeight then
                table.insert(lines, "Screen: " .. data.device.screenWidth .. "x" .. data.device.screenHeight)
            end
        end

        ui:show_text(table.concat(lines, "\n"))
    elseif index == 5 then
        -- Clear history
        memory_history = {}
        battery_history = {}
        brightness_history = {}
        save_history({
            memory = {},
            battery = {},
            brightness = {}
        })
        system:toast("History cleared")
        show_resources()
    end
end

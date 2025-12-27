# AIO Launcher Widget Development Knowledge Base

> Comprehensive API reference, patterns, and examples for AIO Launcher Lua widget development

## Table of Contents

1. [API Reference](#api-reference)
2. [Widget Types](#widget-types)
3. [Special Tools](#special-tools)
4. [Graphing & Charts](#graphing--charts)
5. [Rich UI System](#rich-ui-system)
6. [Built-in Components](#built-in-components)
7. [Code Patterns](#code-patterns)
8. [External Resources](#external-resources)

---

## API Reference

### UI Module (Widget Scripts Only)

#### Display Functions

| Method | Description | Parameters |
|--------|-------------|------------|
| `ui:show_text(text)` | Display plain text | `string` |
| `ui:show_lines(lines, [senders])` | Display list like mail widget | `table, [table]` |
| `ui:show_table(table, [main_col], [center])` | Display table data | `table, [int], [bool]` |
| `ui:show_buttons(names, [colors])` | Display button list | `table, [table]` |
| `ui:show_progress_bar(text, cur, max, [color])` | Show progress indicator | `string, int, int, [hex]` |
| `ui:show_chart(points, [format], [title], [grid])` | Render chart | `table, [string], [string], [bool]` |
| `ui:show_image(uri)` | Display image from URL | `string` |
| `ui:show_toast(text)` | Show notification message | `string` |
| `ui:show_context_menu(items)` | Display context menu | `table` |
| `ui:build(components)` | Construct from AIO components | `table` |

#### State Management

| Method | Description | Returns |
|--------|-------------|---------|
| `ui:set_title(text)` | Change widget title | - |
| `ui:default_title()` | Get standard title from metadata | `string` |
| `ui:set_expandable()` | Show expand button | - |
| `ui:is_expanded()` | Check expanded state | `bool` |
| `ui:is_folded()` | Check folded state | `bool` |
| `ui:set_progress(float)` | Set progress indicator (0-1) | - |
| `ui:set_edit_mode_buttons(icons)` | Add edit mode icons | - |

### HTTP Module

#### Request Methods

```lua
-- GET request
http:get(url, [id])

-- POST request
http:post(url, body, media_type, [id])

-- PUT request
http:put(url, body, media_type, [id])

-- DELETE request
http:delete(url, [id])

-- Set headers for all requests
http:set_headers(headers_table)
```

#### Response Callbacks

```lua
function on_network_result(body, code, headers) end
function on_network_result_<id>(body, code, headers) end
function on_network_error(error_message) end
function on_network_error_<id>(error_message) end
```

### Storage Module

```lua
-- Store value
storage:put(key, value)

-- Retrieve value
local value = storage:get(key)
```

### System Module

#### Device Control

| Method | Description |
|--------|-------------|
| `system:open_browser(url)` | Open URL in browser |
| `system:exec(cmd, [id])` | Execute shell command |
| `system:su(cmd, [id])` | Execute as root |
| `system:vibrate(ms)` | Trigger vibration |
| `system:alarm_sound(seconds)` | Play alarm tone |
| `system:share_text(text)` | Open share dialog |

#### Information Retrieval

| Method | Returns |
|--------|---------|
| `system:location()` | Saved location |
| `system:request_location()` | Triggers `on_location_result` |
| `system:lang()` | System language code |
| `system:tz()` | TimeZone string |
| `system:tz_offset()` | Offset in seconds |
| `system:currency()` | Currency code |
| `system:battery_info()` | Battery details table |
| `system:system_info()` | System info table |
| `system:network_state()` | Network status table |

#### Clipboard

```lua
system:to_clipboard(text)  -- Copy
system:clipboard()         -- Paste/retrieve
```

### Android Module

```lua
-- Get battery info
local battery = android.getBattery()
-- Returns: { level, isCharging, temperature, ... }
```

### Calendar Module

```lua
calendar:events([start], [end], [calendars])  -- Get events
calendar:calendars()                          -- List calendars
calendar:request_permission()                 -- Request access
calendar:show_event_dialog(id)                -- Edit event
calendar:open_event(id)                       -- Open in system app
calendar:open_new_event([start], [end])       -- Create new
calendar:add_event(event_table)               -- Add event
calendar:is_holiday(date)                     -- Check holiday
```

### Tasks Module

```lua
tasks:load()              -- Load all -> on_tasks_loaded()
tasks:add(task_table)     -- Add task
tasks:remove(task_id)     -- Delete task
tasks:save(task_table)    -- Update task
tasks:show_editor(id)     -- Open editor
```

### Notes Module

```lua
notes:load()              -- Load all -> on_notes_loaded()
notes:add(note_table)     -- Add note
notes:remove(note_id)     -- Delete note
notes:save(note_table)    -- Update note
notes:colors()            -- Get color palette
notes:show_editor(id)     -- Open editor
```

### Apps Module

```lua
apps:apps([sort_by])              -- All apps (abc|launch_count|launch_time|install_time)
apps:app(package_name)            -- Specific app info
apps:launch(package)              -- Launch app
apps:show_edit_dialog(package)    -- App editor
apps:categories()                 -- Category list
```

### Dialogs Module

```lua
dialogs:show_dialog(title, text, [btn1], [btn2])
dialogs:show_edit_dialog(title, [text], [default])
dialogs:show_radio_dialog(title, lines, [index])
dialogs:show_checkbox_dialog(title, lines, [checked])
dialogs:show_list_dialog(prefs)
dialogs:show_rich_editor(prefs)
```

### Files Module

```lua
files:read(name)          -- Read script file
files:write(name, data)   -- Write script file
files:delete(name)        -- Delete script file
files:pick_file([mime])   -- Open file picker -> on_file_picked()
files:read_uri(uri)       -- Read content URI
```

### Intent Module

```lua
intent:start_activity({
    action = "android.intent.action.VIEW",
    data = "https://example.com",
    package = "com.example.app",
    extras = { key = "value" }
})

intent:send_broadcast({ action = "...", extras = {...} })
```

---

## Widget Types

### 1. Widget Scripts
- Added to desktop via side menu
- File location: `/sdcard/Android/data/ru.execbit.aiolauncher/files/`
- Callbacks: `on_load()`, `on_resume()`, `on_alarm()`, `on_click()`, `on_long_click()`

### 2. Search Scripts
- Add results to search box
- Enable in settings
- Callbacks: `on_load()`, `on_search(query)`, `on_click(idx)`
- Use `-- prefix="yt|youtube"` for prefix matching

### 3. Side Menu Scripts
- Modify the drawer/side menu
- Callbacks: `on_drawer_open()`, `on_click(idx)`, `on_button_click(idx)`

---

## Special Tools

### Calculator Widget

Simple expression evaluator using Lua's `load()`:

```lua
local function sqrt(x) return math.sqrt(x) end
local function pow(x, y) return math.pow(x, y) end

local function calculate_string(str)
    local fn = load("return " .. str)
    if fn then
        return fn()
    end
    return nil
end

function on_alarm()
    ui:show_text("Enter an expression")
end

function on_click()
    dialogs:show_edit_dialog("Calculator", "Enter expression")
end

function on_dialog_action(text)
    if not text or text == "" then
        on_alarm()
        return
    end
    local result = calculate_string(text)
    if result then
        ui:show_text(text .. " = " .. tostring(result))
    else
        ui:show_text("Invalid expression")
    end
end
```

### Unit Converter

Key pattern: Category-based conversion with temperature special handling:

```lua
local units = {
    length = {
        meter_m = 1,
        kilometer_km = 1e3,
        centimeter_cm = 1e-2,
        inch_in = 0.0254,
        foot_ft = 0.3048,
        mile_mi = 1609.344
    },
    weight = {
        kilogram_kg = 1,
        gram_g = 1e-3,
        pound_lb = 0.453592,
        ounce_oz = 0.0283495
    },
    temperature = {
        celsius_C = "C",
        fahrenheit_F = "F",
        kelvin_K = "K"
    }
}

-- Temperature requires special formulas
local temp_convert = {
    C_to_F = function(c) return c * 9/5 + 32 end,
    F_to_C = function(f) return (f - 32) * 5/9 end,
    C_to_K = function(c) return c + 273.15 end,
    K_to_C = function(k) return k - 273.15 end
}
```

---

## Graphing & Charts

### Basic Chart Usage

```lua
-- Simple array of values
local data = {10, 25, 15, 30, 20}
ui:show_chart(data, nil, "My Chart", true)

-- With timestamp data
local points = {
    { 1628501740654, 123456789 },  -- {timestamp_ms, value}
    { 1628503740654, 300000000 },
    { 1628505740654, 987654321 }
}
ui:show_chart(points, "x:date y:number", "Timeline Chart", true)
```

### Chart Format Options

| Format | Description |
|--------|-------------|
| `nil` or omit | Auto-detect |
| `"number"` | Integer values |
| `"float"` | Decimal values |
| `"date"` | Date timestamps |
| `"time"` | Time values |
| `"none"` | No formatting |
| `"x:date y:number"` | Axis-specific formatting |

### Mini Sparkline Graph Pattern

```lua
local function miniGraph(prices, width)
    width = width or 15
    local bars = "▁▂▃▄▅▆▇█"

    if not prices or #prices == 0 then
        return string.rep("▁", width)
    end

    local min, max = math.huge, -math.huge
    for _, v in ipairs(prices) do
        if v < min then min = v end
        if v > max then max = v end
    end

    local range = max - min
    if range == 0 then range = 1 end

    local graph = ""
    local startIdx = math.max(1, #prices - width + 1)
    for i = startIdx, #prices do
        local normalized = (prices[i] - min) / range
        local barIdx = math.min(8, math.floor(normalized * 7) + 1)
        graph = graph .. bars:sub(barIdx, barIdx)
    end

    return graph
end

-- Usage: "📈 " .. miniGraph({10,20,15,25,30}, 10)
```

### Progress Bar Visualization

```lua
local function progressBar(current, max, width)
    width = width or 10
    local percent = current / max
    local filled = math.floor(percent * width)
    local bar = string.rep("█", filled) .. string.rep("░", width - filled)
    return bar .. " " .. math.floor(percent * 100) .. "%"
end

-- Usage
ui:show_progress_bar("Loading...", 75, 100, "#4CAF50")
```

---

## Rich UI System

### Basic Structure

```lua
local my_gui = gui({
    {"text", "Title", {size = 21, gravity = "center_h", color = "#FFFFFF"}},
    {"new_line", 1},
    {"button", "Click Me", {color = "#4CAF50", expand = true}},
    {"spacer", 2},
    {"icon", "fa:star", {size = 24, color = "#FFD700"}},
    {"new_line"},
    {"progress", "", {progress = 0.75, color = "#2196F3"}}
})

function on_resume()
    my_gui.render()
end

function on_click(idx)
    -- Handle element click by index
end
```

### Element Types

| Type | Properties |
|------|------------|
| `text` | size, color, gravity, font_padding, margin, offset |
| `button` | color, gravity, expand, margin, offset |
| `icon` | size, color, gravity, margin, offset, fixed_width |
| `progress` | progress (0-1), color, margin, offset |
| `new_line` | spacing (units of 4px) |
| `spacer` | horizontal gap size |

### Gravity Options

Combine with `|`: `"top|right"`, `"center_h|center_v"`, `"anchor_prev"`

Values: `left`, `top`, `right`, `bottom`, `center_h`, `center_v`, `anchor_prev`

### Icon Types

```lua
{"icon", "fa:heart", {...}}           -- FontAwesome
{"icon", "app:com.package.name", {...}} -- App icon
{"icon", "contact:lookup_key", {...}}   -- Contact photo
{"icon", "svg:<svg>...</svg>", {...}}   -- Inline SVG
```

---

## Built-in Components

### Using ui:build()

```lua
function on_resume()
    ui:build{
        "text <b>Dashboard</b>",
        "space 2",
        "battery",
        "space",
        "notes 3",
        "space 2",
        "exchange 10 usd eur",
        "space",
        "worldclock new_york london tokyo",
        "space 2",
        "calendar",
        "space",
        "weather 5",
        "space 2",
        "apps 4"
    }
end
```

### Available Components

| Component | Parameters | Description |
|-----------|------------|-------------|
| `text` | HTML content | Display formatted text |
| `space` | [multiplier] | Vertical spacing |
| `battery` | - | Battery indicator |
| `notes` | [count] | Recent notes |
| `tasks` | [count] | Tasks list |
| `calendar` | - | Calendar events |
| `weather` | [days] | Weather forecast |
| `exchange` | amount from to | Currency exchange |
| `worldclock` | tz1 tz2 ... | World time zones |
| `apps` | [count] | Recent/frequent apps |
| `appcategories` | [count] | App categories |
| `player` | - | Media player controls |
| `alarm` | - | Next alarm |
| `clock` | - | Current time |
| `traffic` | - | Data usage |
| `ram` | - | RAM usage |
| `nand` | - | Storage usage |
| `screen` | - | Screen time |
| `timer` | - | Timer widget |
| `stopwatch` | - | Stopwatch widget |
| `calculator` | - | Calculator |
| `finance` | - | Finance tracker |
| `contacts` | - | Quick contacts |
| `health` | - | Health data |

---

## Code Patterns

### 1. State Machine Pattern

```lua
local state = {
    loading = false,
    error = nil,
    data = nil
}

local function render()
    if state.loading then
        ui:show_text("⏳ Loading...")
        return
    end

    if state.error then
        ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
        return
    end

    if state.data then
        -- Display data
        ui:show_text(format_data(state.data))
    else
        ui:show_text("No data available")
    end
end
```

### 2. Persistent Storage Pattern

```lua
local STORAGE_KEY = "my_widget_data"

local function load_data()
    local raw = storage:get(STORAGE_KEY)
    if raw then
        return json.decode(raw) or {}
    end
    return {}
end

local function save_data(data)
    storage:put(STORAGE_KEY, json.encode(data))
end
```

### 3. HTTP API Pattern

```lua
local function fetch_data()
    state.loading = true
    render()

    http:get("https://api.example.com/data", "main")
end

function on_network_result_main(body, code)
    state.loading = false

    if code ~= 200 then
        state.error = "HTTP " .. code
        render()
        return
    end

    local data = json.decode(body)
    if data then
        state.data = data
        state.error = nil
    else
        state.error = "Invalid response"
    end

    render()
end

function on_network_error_main(err)
    state.loading = false
    state.error = err or "Network error"
    render()
end
```

### 4. History Tracking Pattern

```lua
local MAX_HISTORY = 24
local history = {}

local function add_to_history(value)
    table.insert(history, value)
    if #history > MAX_HISTORY then
        table.remove(history, 1)
    end
end

local function get_average()
    if #history == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(history) do
        sum = sum + v
    end
    return sum / #history
end

local function get_trend()
    if #history < 2 then return "stable" end
    local recent = history[#history]
    local previous = history[#history - 1]
    if recent > previous then return "rising"
    elseif recent < previous then return "falling"
    else return "stable"
    end
end
```

### 5. Context Menu Pattern

```lua
function on_long_click()
    ui:show_context_menu({
        "🔄 Refresh",
        "⚙️ Settings",
        "📊 Statistics",
        "🗑️ Clear Data",
        "ℹ️ About"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        refresh_data()
    elseif index == 2 then
        show_settings()
    elseif index == 3 then
        show_statistics()
    elseif index == 4 then
        clear_data()
    elseif index == 5 then
        show_about()
    end
end
```

### 6. Multi-View Pattern

```lua
local views = {"main", "details", "settings"}
local current_view = "main"

local function render()
    if current_view == "main" then
        render_main()
    elseif current_view == "details" then
        render_details()
    elseif current_view == "settings" then
        render_settings()
    end
end

function on_click(idx)
    if current_view == "main" then
        current_view = "details"
    else
        current_view = "main"
    end
    render()
end
```

---

## External Resources

### Official Documentation
- **Main API Docs**: https://github.com/zobnin/aiolauncher_scripts
- **Rich UI Guide**: https://github.com/zobnin/aiolauncher_scripts/blob/master/README_RICH_UI.md
- **App Widgets**: https://github.com/zobnin/aiolauncher_scripts/blob/master/README_APP_WIDGETS.md

### Sample Scripts Repository
- **Main widgets**: https://github.com/zobnin/aiolauncher_scripts/tree/master/main
- **Samples**: https://github.com/zobnin/aiolauncher_scripts/tree/master/samples

### Notable Samples
| File | Description |
|------|-------------|
| `calc.lua` | Calculator with expression evaluation |
| `unit-converter.lua` | Multi-category unit conversion |
| `chart-sample.lua` | Chart/graph demonstration |
| `meta-widget.lua` | Dynamic widget builder |
| `rich-gui-sample.lua` | Rich UI demonstration |
| `build_ui_sample.lua` | Built-in component usage |
| `btc-widget.lua` | Bitcoin price tracker |
| `rss-widget.lua` | RSS feed reader |

### Included Libraries
| Library | Purpose |
|---------|---------|
| `json` | JSON parsing |
| `csv` | CSV parsing |
| `xml` | XML parsing |
| `html` | HTML parsing |
| `url` | URL encoding/decoding |
| `fmt` | HTML formatting |
| `utf8` | UTF-8 support |
| `md_colors` | Material Design colors |
| `luaDate` | Date/time functions |
| `LuaFun` | Functional programming |

---

## Widget Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│                    Widget Lifecycle                      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────┐                                          │
│  │ on_load  │ ──── First time script loads (v5.2.3+)   │
│  └────┬─────┘                                          │
│       │                                                 │
│       ▼                                                 │
│  ┌───────────┐                                         │
│  │ on_resume │ ◄─── Return to desktop (every time)     │
│  └─────┬─────┘                                         │
│        │                                                │
│        ▼                                                │
│  ┌──────────┐                                          │
│  │ on_alarm │ ──── Periodic refresh (max 30 min)       │
│  └────┬─────┘                                          │
│       │                                                 │
│       ▼                                                 │
│  ┌─────────┐      ┌───────────────┐                    │
│  │ on_tick │ ──── │ Every second  │                    │
│  └─────────┘      │ while visible │                    │
│                   └───────────────┘                    │
│                                                         │
│  User Interactions:                                     │
│  ┌──────────┐     ┌───────────────┐                    │
│  │ on_click │ ──► │ Element tap   │                    │
│  └──────────┘     └───────────────┘                    │
│  ┌────────────────┐ ┌─────────────┐                    │
│  │ on_long_click  │►│ Long press  │                    │
│  └────────────────┘ └─────────────┘                    │
│  ┌─────────────────────┐ ┌────────────────┐            │
│  │ on_context_menu_click│►│ Menu selection │            │
│  └─────────────────────┘ └────────────────┘            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Current Repository Widgets

### Core Widgets
| Widget | Description |
|--------|-------------|
| `battery_graph.lua` | Battery tracking with chart |
| `network_graph.lua` | MikroTik network traffic graph |
| `crypto_prices.lua` | Binance crypto tracker |
| `weather.lua` | Weather display |
| `widget_generator.lua` | AI-powered widget generator |

### MikroTik Suite
| Widget | Description |
|--------|-------------|
| `mikrotik.lua` | Core MikroTik status |
| `mikrotik_firewall.lua` | Firewall rules manager |
| `mikrotik_queue.lua` | Queue/bandwidth monitor |
| `mikrotik_logs.lua` | System log viewer |
| `mikrotik_vpn.lua` | VPN status dashboard |

### Productivity Suite
| Widget | Description |
|--------|-------------|
| `task_manager.lua` | Todo list with priorities |
| `calendar_events.lua` | iCal/manual events |
| `pomodoro_timer.lua` | Focus timer |
| `habit_tracker.lua` | Habit tracking |

### Health & Wellness
| Widget | Description |
|--------|-------------|
| `water_tracker.lua` | Hydration tracking |
| `sleep_tracker.lua` | Sleep logging |

### Data & Analytics
| Widget | Description |
|--------|-------------|
| `rss_reader.lua` | RSS/Atom feed reader |
| `api_dashboard.lua` | Custom REST API display |
| `server_stats.lua` | Server monitoring |

---

*Last updated: December 2024*
*Repository: https://github.com/Danz17/AIO-Launcher-Widget*

---

## Tasker & ADB Integration

AIO Launcher supports remote control via broadcasts and scripted commands.

### Broadcast Commands

```bash
# Refresh all widgets
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "refresh"

# Add a widget
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "add_widget:my_widget.lua"

# Execute script command
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "script:widget_name:custom_cmd"
```

### Lua Tasker API

```lua
-- List available Tasker tasks
local tasks = tasker:tasks()

-- Run a Tasker task
tasker:run_task("Task Name")

-- Get a Tasker variable
local value = tasker:get("%Variable")
```

See [docs/TASKER_COMMANDS.md](docs/TASKER_COMMANDS.md) for complete reference.

---

## Plugin APIs

AIO Launcher supports optional plugins that extend functionality.

### Phone Plugin (`ru.execbit.aiosmscallslog`)

```lua
-- Get contacts
local contacts = phone:get_contacts()

-- Make a call
phone:make_call("123456789")

-- Send SMS
phone:send_sms("123456789", "Hello!")

-- Get call log
local calls = phone:get_calls()
```

### Health Plugin (`ru.execbit.aiohealth`)

```lua
-- Get step count
local steps = health:get_steps()

-- Get heart rate
local hr = health:get_heart_rate()
```

### SSH Plugin (`ru.execbit.aiosshbuttons`)

```lua
-- Execute SSH command
ssh:exec("hostname", callback)
```

See [docs/PLUGINS.md](docs/PLUGINS.md) for complete plugin documentation.

---

## Emulator Features

The local emulator (`aio-lua-emulator/`) provides:

### Features
- **Monaco Editor** - Full syntax highlighting
- **Live Preview** - Real-time widget rendering
- **Mock HTTP** - Simulate API responses
- **Device Deployment** - Push widgets to connected Android devices
- **AI Generator** - Create widgets from descriptions

### Device Deployment

The emulator can detect connected ADB devices and deploy widgets directly:

1. Connect device via ADB (`adb connect IP:PORT`)
2. Select device from dropdown in emulator
3. Click "Deploy" to push current widget

### Running the Emulator

```bash
cd aio-lua-emulator
npm install
node server.js
# Open http://localhost:3000
```

---

## Default Scripts Repository

The `Widgets/default/` folder contains 280+ official scripts for reference:

| Folder | Count | Description |
|--------|-------|-------------|
| `main/` | 13 | Production widgets |
| `samples/` | 150+ | Code examples & demos |
| `lib/` | 10+ | Reusable libraries |
| `community/` | 20+ | User contributions |
| `store/` | 100+ | Script store content |

### Key Reference Scripts

- `samples/chart-sample.lua` - Chart API examples
- `samples/rich-gui-sample.lua` - Rich UI patterns
- `samples/meta-widget.lua` - Dynamic ui:build
- `samples/http-sample.lua` - HTTP requests
- `samples/tasker-*.lua` - Tasker integration

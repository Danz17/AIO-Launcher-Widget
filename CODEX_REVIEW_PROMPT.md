# Codex Knowledge Base Update: AIO Launcher Widget Development

## Mission

You are tasked with reviewing, analyzing, and documenting the complete AIO Launcher Lua widget development ecosystem. Your goal is to:

1. **Analyze** all Lua widget code for patterns, best practices, and common pitfalls
2. **Document** the complete API reference with accurate signatures and examples
3. **Extract** reusable code patterns and helper functions
4. **Identify** any bugs, improvements, or inconsistencies
5. **Update** your knowledge base with accurate, tested information about AIO Launcher widget development

---

## Context: What is AIO Launcher?

AIO Launcher is an Android launcher app that supports custom Lua-scripted widgets. These widgets can:
- Display dynamic text, charts, progress bars, and buttons
- Make HTTP requests to external APIs
- Store persistent data locally
- Respond to user interactions (tap, long-press, context menus)
- Access system information (battery, network, etc.)

**Official Resources:**
- App: https://aiolauncher.app
- Widget API Docs: https://aiolauncher.app/api.html
- Widget Repository: https://github.com/AIOLauncher/Widgets

---

## Repository Structure to Review

```
AIO-Launcher-Widget/
├── Widgets/                    # All Lua widget files
│   ├── water_tracker.lua       # Daily water intake tracking
│   ├── sleep_tracker.lua       # Sleep/wake time logging
│   ├── pomodoro_timer.lua      # 25/5 focus timer
│   ├── habit_tracker.lua       # Multi-habit streak tracking
│   ├── rss_reader.lua          # RSS/Atom feed reader
│   ├── api_dashboard.lua       # Custom REST API display
│   ├── server_stats.lua        # Server monitoring
│   ├── task_manager.lua        # Todo list with priorities
│   ├── calendar_events.lua     # iCal/manual events
│   ├── widget_generator.lua    # AI widget generator
│   ├── test_widget.lua         # API testing widget
│   ├── weather.lua             # Weather display
│   ├── crypto_prices.lua       # Cryptocurrency prices
│   ├── stocks.lua              # Stock market widget
│   ├── forex_rates.lua         # Forex exchange rates
│   ├── prayer_times.lua        # Islamic prayer times
│   ├── github_activity.lua     # GitHub activity feed
│   ├── quick_notes.lua         # Quick notes storage
│   ├── speedtest.lua           # Network speed test
│   ├── battery_graph.lua       # Battery monitoring
│   ├── network_graph.lua       # Network traffic graph
│   ├── system_resources.lua    # System resource monitor
│   ├── device_monitor.lua      # Device info display
│   ├── uptime_monitor.lua      # System uptime tracking
│   ├── wifi_analyzer.lua       # WiFi signal analysis
│   └── Mikrotik/               # MikroTik router widgets
│       ├── mikrotik.lua        # Main router monitor
│       ├── mikrotik_firewall.lua
│       ├── mikrotik_queue.lua
│       ├── mikrotik_logs.lua
│       └── mikrotik_vpn.lua
│
├── aio-lua-emulator/           # Web-based widget emulator
│   ├── server.js               # Express server + Fengari Lua
│   └── public/
│       ├── index.html          # UI with Monaco editor
│       ├── app.js              # Emulator logic + templates
│       └── style.css           # Styling
│
└── Docs/                       # Documentation
    └── API_Reference.md        # API documentation
```

---

## Complete AIO Launcher Lua API Reference

### 1. UI Functions

```lua
-- Display text content
ui:show_text(text: string)

-- Display array of lines
ui:show_lines(lines: table, [colors: table])

-- Display clickable buttons
ui:show_buttons(buttons: table, [colors: table])

-- Display a chart/graph
ui:show_chart(values: table, [labels: table], [title: string], [show_labels: boolean])

-- Display progress bar
ui:show_progress_bar(label: string, value: number, max: number, [color: string])

-- Show context menu popup
ui:show_context_menu(items: table)

-- Show editable table
ui:show_table(data: table, [editable: boolean])
```

### 2. HTTP Functions

```lua
-- GET request
http:get(url: string, callback: function(body: string, code: number))

-- GET with headers
http:get(url: string, headers: table, callback: function(body: string, code: number))

-- POST request
http:post(url: string, body: string, callback: function(response: string, code: number))

-- POST with headers
http:post(url: string, body: string, headers: table, callback: function(response: string, code: number))
```

### 3. Storage Functions

```lua
-- Get stored value (returns string or nil)
storage:get(key: string) -> string|nil

-- Store value (value must be string)
storage:put(key: string, value: string)
```

### 4. JSON Functions

```lua
-- Parse JSON string to Lua table
json.decode(json_string: string) -> table|nil

-- Convert Lua table to JSON string
json.encode(table: table) -> string
```

### 5. System Functions

```lua
-- Show toast notification
system:toast(message: string)

-- Open URL in browser
system:open_browser(url: string)

-- Get clipboard content
system:clipboard() -> string

-- Copy to clipboard
system:copy_to_clipboard(text: string)

-- Vibrate device
system:vibrate(duration_ms: number)

-- Get system info
system:get_info(key: string) -> string
-- Keys: "battery_level", "battery_charging", "wifi_ssid", "wifi_signal", etc.
```

### 6. Required Callbacks

```lua
-- Called when widget becomes visible
function on_resume()
end

-- Called on single tap
function on_click()
end

-- Called on long press
function on_long_click()
end

-- Called when context menu item selected
function on_context_menu_click(index: number)
end

-- Called when button clicked
function on_button_click(index: number)
end

-- Called periodically (if widget uses alarm)
function on_alarm()
end
```

---

## Code Patterns to Learn

### Pattern 1: Safe JSON Decoding
```lua
local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end
```

### Pattern 2: Persistent Storage with JSON
```lua
local STORAGE_KEY = "my_widget_data"

local function load_data()
  local data = storage:get(STORAGE_KEY)
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return { default = "values" }
end

local function save_data(data)
  storage:put(STORAGE_KEY, json.encode(data))
end
```

### Pattern 3: Daily Reset Logic
```lua
local function get_today()
  return os.date("%Y-%m-%d")
end

local function reset_if_new_day(saved)
  local today = get_today()
  if saved.last_date ~= today then
    -- Archive yesterday's data
    if saved.last_date ~= "" then
      table.insert(history, { date = saved.last_date, value = saved.today_value })
    end
    -- Reset for new day
    today_value = 0
    current_date = today
  end
end
```

### Pattern 4: Progress Bar Helper
```lua
local function progress_bar(value, max, width)
  width = width or 10
  if max == 0 then max = 1 end
  local pct = math.min(value / max, 1)
  local filled = math.floor(pct * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end
```

### Pattern 5: Byte Formatting
```lua
local function format_bytes(bytes)
  bytes = tonumber(bytes) or 0
  if bytes >= 1073741824 then
    return string.format("%.1f GB", bytes / 1073741824)
  elseif bytes >= 1048576 then
    return string.format("%.1f MB", bytes / 1048576)
  elseif bytes >= 1024 then
    return string.format("%.1f KB", bytes / 1024)
  else
    return string.format("%d B", bytes)
  end
end
```

### Pattern 6: HTTP API with Error Handling
```lua
local function fetch_data()
  state.loading = true
  state.error = nil
  render()

  http:get(API_URL, function(body, code)
    state.loading = false

    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.data = data
        state.last_refresh = os.time()
      else
        state.error = "Failed to parse response"
      end
    else
      state.error = "Request failed (code: " .. tostring(code) .. ")"
    end

    render()
  end)
end
```

### Pattern 7: MikroTik REST API Authentication
```lua
local CONFIG = {
  ip = "10.1.1.1",
  user = "admin",
  pass = "password"
}

local function get_url(endpoint)
  return string.format("http://%s:%s@%s%s",
    CONFIG.user, CONFIG.pass, CONFIG.ip, endpoint)
end

-- Usage
http:get(get_url("/rest/system/resource"), callback)
```

### Pattern 8: Streak Calculation
```lua
local function get_streak(habit_id)
  local streak = 0
  if today_status[habit_id] then
    streak = 1
  else
    return 0  -- Streak broken
  end
  for i = #history, 1, -1 do
    local found = false
    for _, id in ipairs(history[i].completed or {}) do
      if id == habit_id then found = true; break end
    end
    if found then streak = streak + 1 else break end
  end
  return streak
end
```

### Pattern 9: RSS/XML Parsing (Pattern Matching)
```lua
local function parse_feed(xml)
  local items = {}

  -- RSS format
  for item in xml:gmatch("<item[^>]*>(.-)</item>") do
    local title = item:match("<title[^>]*><!%[CDATA%[(.-)%]%]>") or
                  item:match("<title[^>]*>(.-)</title>")
    local link = item:match("<link[^>]*>(.-)</link>")
    if title then
      table.insert(items, { title = strip_html(title), link = link })
    end
  end

  -- Atom format fallback
  if #items == 0 then
    for entry in xml:gmatch("<entry[^>]*>(.-)</entry>") do
      -- Similar parsing...
    end
  end

  return items
end
```

### Pattern 10: Widget State Machine
```lua
local state = {
  loading = false,
  error = nil,
  data = nil,
  view_mode = "list",  -- list, detail, stats
  filter = "all"
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

  if state.view_mode == "list" then
    render_list()
  elseif state.view_mode == "detail" then
    render_detail()
  elseif state.view_mode == "stats" then
    render_stats()
  end
end
```

---

## Review Instructions

### Step 1: Read All Widget Files
For each `.lua` file in the `Widgets/` directory:
1. Identify the widget's purpose
2. Document its features
3. Extract reusable patterns
4. Note any API usage
5. Identify potential bugs or improvements

### Step 2: Verify API Accuracy
Cross-reference the API usage in widgets against:
- Official AIO Launcher documentation
- The emulator's mock implementations
- Common patterns that work consistently

### Step 3: Document Best Practices
Based on the code review, document:
- Recommended widget structure
- Error handling patterns
- Performance optimizations
- UI/UX conventions (emoji usage, separators, etc.)

### Step 4: Identify Common Mistakes
Look for and document:
- Incorrect API usage (e.g., `json:decode()` vs `json.decode()`)
- Missing error handling
- Memory leaks or performance issues
- UI inconsistencies

### Step 5: Create Knowledge Base Entry
Output a structured knowledge base entry covering:
1. **API Reference** - Complete, accurate, with examples
2. **Widget Templates** - Starter code for common widget types
3. **Code Snippets** - Reusable helper functions
4. **Best Practices** - Do's and don'ts
5. **Troubleshooting** - Common issues and solutions

---

## Expected Output Format

```markdown
# AIO Launcher Widget Development Knowledge Base

## 1. API Reference
[Complete API documentation with signatures, parameters, return values, and examples]

## 2. Widget Architecture
[Standard widget structure, state management, lifecycle]

## 3. Code Patterns Library
[Categorized, reusable code patterns with explanations]

## 4. Best Practices
[Guidelines for writing robust, performant widgets]

## 5. Common Pitfalls
[Mistakes to avoid with explanations]

## 6. Widget Catalog
[Summary of all reviewed widgets with features]

## 7. Emulator Usage
[How to use the web-based emulator for development]
```

---

## Additional Context

### MikroTik REST API Endpoints Used
- `/rest/system/resource` - CPU, RAM, uptime
- `/rest/interface/lte` - LTE modem info
- `/rest/ip/hotspot/active` - Hotspot clients
- `/rest/ip/firewall/filter` - Firewall rules
- `/rest/ip/firewall/nat` - NAT rules
- `/rest/ip/firewall/address-list` - Address lists
- `/rest/queue/simple` - Simple queues
- `/rest/queue/tree` - Queue trees
- `/rest/log` - System logs
- `/rest/ppp/active` - Active VPN connections
- `/rest/interface/l2tp-server/server` - L2TP server config
- `/rest/interface/wireguard` - WireGuard interfaces
- `/rest/ip/ipsec/active-peers` - IPsec peers

### External APIs Used in Widgets
- CoinDesk API (Bitcoin prices)
- IPApi.co (IP geolocation)
- wttr.in (Weather)
- WorldTimeAPI (Timezone/time)
- Quotable.io (Random quotes)
- GitHub API (Activity feeds)
- Groq API (AI generation)

---

## Quality Checklist

Before finalizing the knowledge base, verify:

- [ ] All API functions documented with correct signatures
- [ ] All parameters and return types accurate
- [ ] Examples are syntactically correct Lua
- [ ] Patterns handle edge cases (nil, empty, errors)
- [ ] Best practices reflect actual working code
- [ ] Common mistakes are based on real issues found
- [ ] Widget catalog covers all 25+ widgets
- [ ] Emulator features documented

---

**Begin your comprehensive review now. Read each file, analyze patterns, and produce an accurate, detailed knowledge base that can be used to train future AI assistants on AIO Launcher widget development.**

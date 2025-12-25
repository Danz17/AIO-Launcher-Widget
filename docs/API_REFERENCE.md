# AIO Launcher Lua API Reference

Complete API reference for AIO Launcher widget scripts.

**Official Documentation:** [github.com/zobnin/aiolauncher_scripts](https://github.com/zobnin/aiolauncher_scripts)

---

## Script Meta Tags

```lua
-- name = "Widget Name"
-- description = "What it does"
-- author = "Your Name"
-- type = "widget"
-- data_source = "script"
-- foldable = "true"
```

---

## Callbacks

| Callback | When Called |
|----------|-------------|
| `on_load()` | First script load |
| `on_resume()` | Every return to desktop |
| `on_alarm()` | Max once per 30 minutes |
| `on_click(index)` | Item/button tapped |
| `on_long_click(index)` | Item long-pressed |
| `on_network_result(body, code)` | HTTP success |
| `on_network_error(error)` | HTTP failure |

---

## UI Module

```lua
ui:show_text(string)                    -- Display text
ui:show_lines(table)                    -- Display line list
ui:show_table(table, main_col, center)  -- Display table
ui:show_buttons(names, colors)          -- Display buttons
ui:show_progress_bar(text, val, max)    -- Progress bar
ui:show_chart(points, format, title)    -- Chart/graph
ui:show_toast(string)                   -- Toast message
ui:show_context_menu(table)             -- Context menu
ui:set_title(string)                    -- Set widget title
```

---

## HTTP Module

```lua
-- GET request
http:get(url)
http:get(url, callback)
http:get(url, headers, callback)

-- POST request
http:post(url, body, callback)
http:post(url, body, headers, callback)

-- Set headers (real device only)
http:set_headers({"Authorization: Bearer xxx"})
```

**Note:** For emulator compatibility, use URL-embedded auth:
```lua
local url = "http://user:pass@192.168.1.1/api"
```

---

## Storage Module

```lua
storage:get(key)         -- Get stored value
storage:put(key, value)  -- Store value
storage:delete(key)      -- Delete value
```

---

## System Module

```lua
system:open_browser(url)      -- Open URL
system:toast(message)         -- Show toast
system:vibrate(ms)            -- Vibrate device
system:copy_to_clipboard(str) -- Copy text
system:clipboard()            -- Get clipboard
system:lang()                 -- System language
system:tz()                   -- Timezone string
system:battery_info()         -- Battery status
system:network_state()        -- Network info
```

---

## JSON Module

```lua
json.encode(table)   -- Table to JSON string
json.decode(string)  -- JSON string to table

-- Safe decoding
local ok, data = pcall(json.decode, body)
```

---

## Android Module (Emulator)

```lua
android.getBattery()          -- {level, isCharging, temperature}
android.getBatteryLevel()     -- Battery %
android.isCharging()          -- Boolean
android.getDeviceInfo()       -- {model, osVersion}
android.getWifiList()         -- WiFi networks
android.getWifiSignal()       -- Signal dBm
android.getConnectedSSID()    -- Connected WiFi
android.getScreenBrightness() -- 0-100
```

---

## Utility Functions

```lua
-- String
string:split(delimiter)
string:trim()
string:starts_with(prefix)
string:ends_with(suffix)

-- Encoding
utils:base64encode(string)
utils:base64decode(string)
utils:md5(string)
utils:sha256(string)

-- Math
round(number, decimals)
```

---

## Common Patterns

### Progress Bar
```lua
local function progress_bar(value, max, width)
  width = width or 10
  local filled = math.floor((value / max) * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end
```

### Format Bytes
```lua
local function format_bytes(bytes)
  if bytes >= 1073741824 then
    return string.format("%.1fGB", bytes / 1073741824)
  elseif bytes >= 1048576 then
    return string.format("%.1fMB", bytes / 1048576)
  else
    return string.format("%.1fKB", bytes / 1024)
  end
end
```

### Safe HTTP Request
```lua
function on_network_result(body, code)
  if code ~= 200 or not body then
    ui:show_text("Error: " .. tostring(code))
    return
  end
  local ok, data = pcall(json.decode, body)
  if ok and data then
    -- process data
  end
end
```

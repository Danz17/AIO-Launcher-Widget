# AIO Launcher Lua API Reference

Complete technical documentation for AIO Launcher widget scripting.

## Script Metadata

```lua
-- name = "Widget Name"
-- description = "Widget description"
-- type = "widget"  -- or "search", "drawer"
-- foldable = "true"
-- author = "Your Name"
```

## Entry Points

| Function | When Called |
|----------|-------------|
| `on_load()` | First script load (AIO 5.2.3+) |
| `on_resume()` | Every return to desktop |
| `on_alarm()` | Return to desktop, max once per 30 min |
| `on_tick(ticks)` | Every second while launcher visible |

---

## HTTP API

### Request Functions

```lua
http:get(url, [id])
http:post(url, body, media_type, [id])
http:put(url, body, media_type, [id])
http:delete(url, [id])
http:set_headers(table)  -- e.g., {"Cache-Control: no-cache"}
```

### Response Callbacks

**Without ID:**
```lua
function on_network_result(body, code, headers)
    -- body: response string
    -- code: HTTP status (200, 404, etc.)
    -- headers: table with lowercase keys
end

function on_network_error(error_message)
end
```

**With ID:**
```lua
-- If called: http:get("url", "myrequest")
function on_network_result_myrequest(body, code, headers)
end

function on_network_error_myrequest(error_message)
end
```

### Example

```lua
function on_resume()
    http:get("https://api.example.com/data", "api")
end

function on_network_result_api(body, code)
    if code == 200 then
        local data = json:decode(body)
        ui:show_text("Result: " .. data.value)
    end
end
```

---

## UI Functions

### Display Functions

```lua
ui:show_text(string)                -- Plain text display
ui:show_toast(string)               -- Android-style toast message
ui:show_lines(table, [senders])     -- List with optional senders
ui:show_table(table, [main_col], [center])  -- Table display
ui:show_buttons(names, [colors])    -- Button list
ui:show_progress_bar(text, current, max, [color])
ui:show_chart(points, [format], [title], [grid], [unused], [copyright])
ui:show_image(uri)                  -- Image by URL
```

### Title & State

```lua
ui:set_title(string)        -- Change widget title
ui:default_title()          -- Get standard title
ui:set_expandable()         -- Show expand button
ui:is_expanded()            -- Check if expanded
ui:is_folded()              -- Check if folded
ui:set_progress(float)      -- Progress indicator (0.0-1.0)
```

---

## Context Menu

### Display

```lua
ui:show_context_menu({
    { "icon_name", "Menu Item 1" },
    { "icon_name", "Menu Item 2" },
    { "icon_name", "Menu Item 3" }
})
```

**Available icons:** share, copy, trash, refresh, info, settings, close, etc.

**Simple format (may work):**
```lua
ui:show_context_menu({
    "🔄 Refresh",
    "⚙️ Settings",
    "❌ Close"
})
```

### Callback

```lua
function on_context_menu_click(idx)
    -- idx: 0-based or 1-based (verify!)
    if idx == 0 then
        -- First item clicked
    end
end
```

---

## User Interaction Callbacks

```lua
function on_click(number)       -- Tap on element
function on_long_click(number)  -- Long press on element
function on_dialog_action(num)  -- Dialog button (-1 = closed)
function on_action()            -- Swipe right action
function on_settings()          -- Settings icon in edit menu
```

---

## System Functions

```lua
system:open_browser(url)
system:open_app(package_name)
system:exec(command)              -- Shell command
system:clipboard(text)            -- Copy to clipboard
system:vibrate(ms)                -- Vibrate device
system:toast(text)                -- System toast
```

---

## JSON Module

```lua
local data = json:decode(json_string)  -- Parse JSON to table
local str = json:encode(table)         -- Table to JSON string
```

---

## File Paths

Scripts location:
```
/sdcard/Android/data/ru.execbit.aiolauncher/files/
```

---

## Common Patterns

### HTTP with JSON

```lua
function on_resume()
    ui:show_text("Loading...")
    http:get("https://api.example.com/data")
end

function on_network_result(body, code)
    if code == 200 and body then
        local ok, data = pcall(function() return json:decode(body) end)
        if ok and data then
            ui:show_text("Value: " .. tostring(data.value))
        else
            ui:show_text("Parse error")
        end
    else
        ui:show_text("Error: " .. tostring(code))
    end
end
```

### Multiple Requests

```lua
local state = { pending = 0, data1 = nil, data2 = nil }

function on_resume()
    state.pending = 2
    http:get("https://api1.com/data", "api1")
    http:get("https://api2.com/data", "api2")
end

function on_network_result_api1(body, code)
    if code == 200 then
        state.data1 = json:decode(body)
    end
    check_done()
end

function on_network_result_api2(body, code)
    if code == 200 then
        state.data2 = json:decode(body)
    end
    check_done()
end

function check_done()
    state.pending = state.pending - 1
    if state.pending == 0 then
        display_results()
    end
end
```

### Auth with Headers

```lua
function on_resume()
    http:set_headers({
        "Authorization: Bearer YOUR_TOKEN",
        "Content-Type: application/json"
    })
    http:get("https://api.example.com/protected")
end
```

### Basic Auth in URL

```lua
local url = "http://user:password@192.168.1.1/api/data"
http:get(url)
```

---

## Troubleshooting

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `attempt to call nil` | Function doesn't exist | Check function name spelling |
| No response | Callback name wrong | Use exact callback name |
| Parse error | Invalid JSON | Use pcall for safety |

### Debug Tips

1. Use `ui:show_toast()` for quick debugging
2. Check logcat: `adb logcat | grep lua`
3. Test with minimal script first

---

## Sources

- [Official Repo](https://github.com/zobnin/aiolauncher_scripts)
- [README](https://github.com/zobnin/aiolauncher_scripts/blob/master/README.md)
- [Intro Guide](https://github.com/zobnin/aiolauncher_scripts/blob/master/README_INTRO.md)

# AIO Launcher Tasker Integration

Complete reference for Tasker and ADB integration with AIO Launcher.

---

## Broadcast Intent

**Action:** `ru.execbit.aiolauncher.COMMAND`
**Extra:** `cmd` (string containing the command)
**Optional:** `password` (if launcher password protection is enabled)

### ADB Format
```bash
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "<command>"

# With password protection
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "<command>" --es password "YOUR_PASSWORD"
```

### Tasker Format
1. Action: **System > Send Intent**
2. Action: `ru.execbit.aiolauncher.COMMAND`
3. Extra: `cmd:<command>`
4. Target: Broadcast Receiver

---

## Available Commands

### Menu & Navigation

| Command | Description |
|---------|-------------|
| `apps_menu` | Open apps drawer |
| `apps_menu:<style>` | Open with specific style |
| `search` | Open search |
| `headers` | Toggle section headers |
| `shortcuts` | Open shortcuts |
| `quick_menu` | Open quick menu |
| `settings` | Open AIO settings |
| `ui_settings` | Open UI settings |

### Device Control

| Command | Description |
|---------|-------------|
| `screen_off` | Turn screen off (accessibility) |
| `screen_off_root` | Turn screen off (root) |
| `flashlight` | Toggle flashlight |
| `camera` | Open camera |
| `dialer` | Open dialer |
| `voice` | Open voice assistant |

### Launcher Actions

| Command | Description |
|---------|-------------|
| `refresh` | Refresh all widgets |
| `notify` | Show notification |
| `scroll_up` | Scroll up |
| `scroll_down` | Scroll down |
| `scroll_up_or_search` | Scroll up or open search if at top |
| `fold` | Fold all widgets |
| `unfold` | Unfold all widgets |
| `one_handed` | Toggle one-handed mode |
| `private_mode` | Toggle private mode |
| `desktop_lock` | Toggle desktop lock |

### Data Entry

| Command | Description |
|---------|-------------|
| `add_note:<text>` | Add a note |
| `add_task:<text>` | Add a task (no date) |
| `add_task:<text>:<YYYY-MM-DD-HH-MM>` | Add task with date/time |
| `add_purchase:<amount><currency>:<comment>` | Add expense entry |

### Widget Management

| Command | Description |
|---------|-------------|
| `add_widget:<name>` | Add widget to desktop |
| `add_widget:<name>:<position>` | Add widget at position |
| `remove_widget:<position>` | Remove widget at position |

### Profile & Theme

| Command | Description |
|---------|-------------|
| `theme:<name>` | Apply theme |
| `save_profile:<name>` | Save current profile |
| `restore_profile:<name>` | Restore profile |
| `iconpack:<package>` | Apply icon pack |

### Script Commands

Send commands to specific scripts:
```bash
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "script:<script_name>:<command>"
```

---

## Lua Tasker API

### Get Available Tasks
```lua
function on_resume()
    local tasks = tasker:get_tasks()
    ui:show_lines(tasks)
end
```

### Run a Tasker Task
```lua
function on_click(idx)
    tasker:run_task(task_name)
end

-- Handle result
function on_task_result(success)
    if success then
        ui:show_toast("Task completed!")
    else
        ui:show_toast("Task failed!")
    end
end
```

### Check Tasker Availability
```lua
if tasker:is_installed() then
    -- Tasker is available
end
```

---

## Broadcast Events FROM AIO Launcher

Your Tasker profiles can listen for these events:

| Event | Description |
|-------|-------------|
| `ru.execbit.aiolauncher.RESUMED` | Launcher resumed |
| `ru.execbit.aiolauncher.STOPPED` | Launcher stopped |
| `ru.execbit.aiolauncher.SEARCH_OPENED` | Search opened |
| `ru.execbit.aiolauncher.SEARCH_CLOSED` | Search closed |
| `ru.execbit.aiolauncher.DRAWER_OPENED` | App drawer opened |
| `ru.execbit.aiolauncher.DRAWER_CLOSED` | App drawer closed |
| `ru.execbit.aiolauncher.WIDGET_ADDED` | Widget added (includes name) |
| `ru.execbit.aiolauncher.WIDGET_REMOVED` | Widget removed (includes name) |

---

## Widget Control via Tasker

### Add Widget Script
```lua
-- name = "Tasker Widget Control"
-- Receive commands: add=:=<widget_name> or remove=:=<widget_name>

function on_command(cmd)
    local data = cmd:split("=:=")
    local command = data[1]
    local widget_name = data[2]

    if command == "add" then
        aio:add_widget(widget_name)
    elseif command == "remove" then
        aio:remove_widget(widget_name)
    end
end
```

### ADB Command for Script
```bash
# Add widget
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND \
  --es cmd "script:tasker widget control:add=:=crypto_prices"

# Remove widget
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND \
  --es cmd "script:tasker widget control:remove=:=crypto_prices"
```

---

## Application Launch Format

Launch specific apps with optional profile:
```
cn:package.name/Activity.Name:PROFILE_ID
```

Example:
```bash
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND \
  --es cmd "cn:com.spotify.music/.MainActivity"
```

---

## Examples

### Refresh All Widgets
```bash
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "refresh"
```

### Add a Quick Note
```bash
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "add_note:Meeting at 3pm"
```

### Add Task with Due Date
```bash
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "add_task:Doctor appointment:2025-01-15-10-30"
```

### Toggle Screen Off
```bash
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "screen_off"
```

### Apply Dark Theme
```bash
adb shell am broadcast -a ru.execbit.aiolauncher.COMMAND --es cmd "theme:dark"
```

---

## Related Files

- [samples/tasker-test.lua](../Widgets/default/samples/tasker-test.lua) - Basic Tasker integration
- [samples/tasker-widget-control.lua](../Widgets/default/samples/tasker-widget-control.lua) - Widget management
- [samples/tasker-test2.lua](../Widgets/default/samples/tasker-test2.lua) - Advanced examples

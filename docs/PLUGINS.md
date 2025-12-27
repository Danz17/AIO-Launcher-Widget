# AIO Launcher Plugins

Plugins extend AIO Launcher functionality by providing additional APIs for Lua scripts.

---

## Available Plugins

| Plugin | Package | Function |
|--------|---------|----------|
| AIO Calls & SMS | `ru.execbit.aiosmscallslog` | Call logs, SMS, contacts |
| AIO Health | `ru.execbit.aiohealth` | Health/fitness data |
| AIO SSH Buttons | `ru.execbit.aiosshbuttons` | SSH command shortcuts |

### Installation

Download APKs from: https://zobnin.github.io/aiolauncher/plugins.html

---

## Phone API (Built-in + Plugin)

The `phone:` API provides access to calls, SMS, and contacts.

### Methods

| Method | Description |
|--------|-------------|
| `phone:contacts()` | Get all contacts (returns array or "permission_error") |
| `phone:get_contacts()` | Alias for contacts() |
| `phone:request_permission()` | Request contacts permission |
| `phone:make_call(number)` | Initiate phone call |
| `phone:send_sms(number, text)` | Send SMS message |
| `phone:show_contact_dialog(id)` | Show contact details dialog |

### Contact Object

```lua
{
    id = "123",           -- Contact ID
    lookup_key = "abc",   -- Lookup key for contact dialog
    name = "John Doe",    -- Display name
    icon = "base64...",   -- Contact photo (base64) or nil
    number = "+1234..."   -- Phone number
}
```

### Examples

#### List Contacts
```lua
function on_resume()
    local contacts = phone:contacts()

    if contacts == "permission_error" then
        phone:request_permission()
        return
    end

    local names = {}
    for _, c in ipairs(contacts) do
        table.insert(names, c.name)
    end
    ui:show_lines(names)
end

function on_click(idx)
    local contacts = phone:contacts()
    phone:show_contact_dialog(contacts[idx].lookup_key)
end
```

#### Make Call
```lua
function on_click()
    phone:make_call("555-1234")
end
```

#### Send SMS
```lua
function on_click()
    phone:send_sms("555-1234", "Hello from AIO!")
end
```

---

## Call Log Access (Root Required)

For detailed call history without the plugin, use root access:

```lua
-- name = "Call History"
-- root = "true"

function on_resume()
    local cmd = [[content query --uri content://call_log/calls \
        --projection date:number:name:type:duration \
        --sort "date desc limit 10"]]
    system:su(cmd)
end

function on_shell_result(result)
    -- Parse result and display
    ui:show_text(result)
end
```

### Call Types
| Type | Description |
|------|-------------|
| 1 | Incoming |
| 2 | Outgoing |
| 3 | Missed |
| 4 | Cancelled (outgoing, duration=0) |
| 5 | Rejected |
| 6 | Blocked |

---

## Health API (Requires AIO Health Plugin)

Access fitness and health data from Google Fit or similar providers.

### Methods (when plugin installed)

| Method | Description |
|--------|-------------|
| `health:steps()` | Get step count |
| `health:distance()` | Get distance walked |
| `health:calories()` | Get calories burned |
| `health:heart_rate()` | Get heart rate data |

### Example

```lua
function on_resume()
    local steps = health:steps() or 0
    local distance = health:distance() or 0

    ui:show_text(string.format(
        "Steps: %d\nDistance: %.2f km",
        steps, distance / 1000
    ))
end
```

---

## SSH Buttons (Requires AIO SSH Buttons Plugin)

Execute SSH commands on remote servers.

### Configuration

Configure SSH connections in the plugin settings before use.

### Methods (when plugin installed)

| Method | Description |
|--------|-------------|
| `ssh:execute(server, command)` | Run command on server |
| `ssh:list_servers()` | Get configured servers |

### Example

```lua
function on_resume()
    ui:show_buttons({"Restart Web Server", "Check Disk Space"})
end

function on_click(idx)
    if idx == 1 then
        ssh:execute("myserver", "sudo systemctl restart nginx")
    elseif idx == 2 then
        ssh:execute("myserver", "df -h")
    end
end

function on_ssh_result(output)
    ui:show_text(output)
end
```

---

## Permission Handling

Always check for permissions before using phone/contacts:

```lua
local have_permission = false

function on_resume()
    local contacts = phone:contacts()

    if contacts == "permission_error" then
        phone:request_permission()
        ui:show_text("Please grant contacts permission")
        return
    end

    have_permission = true
    -- Continue with contacts...
end

function on_click(idx)
    if not have_permission then return end
    -- Handle click...
end
```

---

## Script Metadata for Plugins

Declare plugin requirements in script header:

```lua
-- name = "My Script"
-- description = "Uses phone features"
-- type = "widget"
-- requires_plugin = "ru.execbit.aiosmscallslog"
-- root = "false"
```

---

## Related Files

- [main/contacts-menu.lua](../Widgets/default/main/contacts-menu.lua) - Contacts in drawer
- [samples/dialer-sample.lua](../Widgets/default/samples/dialer-sample.lua) - Dialer examples
- [community/calllog-ru-root-widget.lua](../Widgets/default/community/calllog-ru-root-widget.lua) - Root call log

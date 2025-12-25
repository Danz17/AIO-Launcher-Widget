# MikroTik Router Widget

Comprehensive Lua widget for monitoring MikroTik routers via the REST API.

## File

**`mikrotik.lua`** - Single comprehensive widget with all features

## Features

- **System Monitoring**
  - CPU usage with progress bar
  - RAM usage with progress bar
  - Uptime display
  - RouterOS version and board name

- **LTE Monitoring** (if available)
  - Signal strength with visual bars
  - Operator name
  - Band information

- **Hotspot Clients**
  - Active user count
  - Top users by data usage
  - Configurable max display

- **Remote Control** (via long-press menu)
  - Toggle LTE on/off
  - Toggle Hotspot on/off
  - Reboot router
  - Open WebFig interface

- **Display Modes**
  - Full mode: detailed information
  - Compact mode: single line overview

## Configuration

Edit the CONFIG table at the top of the file:

```lua
local CONFIG = {
  ip = "10.1.1.1",
  user = "admin",
  pass = "admin123",

  -- Display options
  show_lte = true,
  show_clients = true,
  max_clients = 5,
  compact_mode = false,

  -- Data limits (GB)
  daily_limit = 10,
  monthly_limit = 100
}
```

## Router Setup

Ensure the REST API is enabled on your MikroTik router:

```routeros
/ip service set www disabled=no
```

The widget uses URL-embedded authentication (`http://user:pass@ip/rest/...`) which works with the standard HTTP service.

## Usage

1. Copy `mikrotik.lua` to your AIO Launcher scripts folder
2. Edit the CONFIG section with your router credentials
3. Add the widget to your launcher

**Tap** - Open WebFig in browser (or retry if error)
**Long press** - Open control menu

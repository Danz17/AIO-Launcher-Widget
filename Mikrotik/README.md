# MikroTik Router Widgets

Lua widgets for monitoring MikroTik routers via the REST API.

## Versions

| File | Features | Lines | Recommended |
|------|----------|-------|-------------|
| `mikrotik_full.lua` | Full monitoring, graphs, LTE, hotspot, DHCP, remote control | 609 | **Yes** |
| `mikrotik_simple.lua` | Basic CPU/RAM/uptime only | 53 | For simple needs |
| `mikrotik_widget_v10.lua` | Basic with Base64 auth | 61 | Legacy |
| `mikrotik_v12.lua` | Debug version with auth testing | 71 | Development |
| `mikrotik_widget_v6.lua` | Advanced features, URL auth | 334 | Superseded by full |

## Recommended: `mikrotik_full.lua`

Features:
- CPU/RAM usage with history graphs
- LTE signal strength and operator info
- Hotspot active clients
- DHCP lease monitoring
- Daily/monthly data usage tracking
- Remote control (reboot, enable/disable interfaces)
- Compact and full display modes

## Configuration

Edit the CONFIG table at the top of each file:

```lua
local CONFIG = {
    ip = "10.1.1.1",
    username = "admin",
    password = "your_password",
    -- ... other options
}
```

## Router Setup

Ensure the REST API is enabled on your MikroTik router:

```
/ip service set www-ssl disabled=no
/ip service set api-ssl disabled=no
```

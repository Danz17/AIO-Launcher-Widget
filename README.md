# AIO Launcher Widget Development Kit

A comprehensive development environment for creating and testing **Lua widgets** for [AIO Launcher](https://aiolauncher.app/) - a minimalist Android home screen replacement focused on information density.

## Features

- **6 Ready-to-use Widgets** - WiFi, Crypto, IoT, NAS, Surveillance, Password Manager
- **MikroTik Router Monitor** - Multiple versions for router monitoring
- **Local Emulator** - Test widgets without deploying to Android
- **Web UI** - Visual editor with Monaco (VS Code) integration
- **Mock Data Support** - Test with fake API responses

## Project Structure

```
AIO-Launcher-Widget/
├── Widgets/                    # Production-ready Lua widgets
│   ├── crypto_prices.lua       # Binance cryptocurrency tracker
│   ├── wifi_analyzer.lua       # WiFi network scanner
│   ├── tuya_devices.lua        # Tuya/Smart Life IoT control
│   ├── synology_nas.lua        # Synology NAS monitoring
│   ├── surveillance.lua        # Synology Surveillance Station
│   └── enpass.lua              # Enpass password manager
│
├── Mikrotik/                   # MikroTik router widgets
│   ├── mikrotik_full.lua       # Full-featured (recommended)
│   ├── mikrotik_simple.lua     # Basic monitoring
│   └── mikrotik_widget_v10.lua # Stable version
│
├── aio-lua-emulator/           # Local testing environment
│   ├── emulator.js             # CLI emulator
│   ├── server.js               # Web UI server
│   ├── api/                    # AIO Launcher API emulation
│   ├── mocks/                  # Mock API responses
│   └── public/                 # Web interface
│
└── AIO Backup/                 # AIO Launcher backup data
```

## Quick Start

### 1. Install Dependencies

```bash
cd aio-lua-emulator
npm install
```

### 2. Test a Widget (CLI)

```bash
# Run with mock data
node emulator.js ../Widgets/crypto_prices.lua -m ./mocks/crypto_binance.json

# Interactive mode (simulate clicks)
node emulator.js ../Widgets/wifi_analyzer.lua -i

# Test specific function
node emulator.js ../Mikrotik/mikrotik_full.lua -t on_resume
```

### 3. Web UI (Visual Editor)

```bash
node server.js
# Open http://localhost:3000
```

## Widget Overview

### Crypto Prices (`crypto_prices.lua`)
Track cryptocurrency prices from Binance API with:
- Real-time price updates
- 24h change percentage
- Price history graphs
- Configurable alerts
- Rate limiting protection

### WiFi Analyzer (`wifi_analyzer.lua`)
Scan and analyze nearby WiFi networks:
- Signal strength visualization
- Security type detection
- Channel analysis
- Hidden network detection

### Tuya Devices (`tuya_devices.lua`)
Control Tuya/Smart Life IoT devices:
- OAuth2 authentication
- Device listing and control
- Scene activation
- Status monitoring

### Synology NAS (`synology_nas.lua`)
Monitor Synology NAS systems:
- CPU/RAM usage
- Storage capacity
- Network traffic
- Temperature alerts

### Surveillance Station (`surveillance.lua`)
Monitor Synology Surveillance Station:
- Camera status
- Recording status
- Event notifications

### Enpass (`enpass.lua`)
Password manager integration:
- Vault status
- Security score
- Password generator
- Breach detection

### MikroTik Router (`mikrotik_full.lua`)
Comprehensive router monitoring:
- CPU/RAM usage graphs
- LTE signal strength
- Hotspot client list
- Data usage tracking
- Remote control (reboot, enable/disable interfaces)

## Emulator API Support

| API Module | Functions | Status |
|------------|-----------|--------|
| `ui` | show_text, show_lines, show_buttons, show_table, show_chart, show_progress_bar | ✅ Full |
| `http` | get, post | ✅ Full |
| `json` | encode, decode | ✅ Full |
| `system` | toast, open_browser | ✅ Full |
| `storage` | get, set, delete, keys, clear | ✅ Full |
| `files` | read, write, exists | ✅ Full |
| `android` | getWifiList, getBattery, getLocation | ✅ Mock |

## Creating Your Own Widget

### Basic Widget Template

```lua
-- name = "My Widget"
-- description = "Widget description"
-- type = "widget"

local CONFIG = {
    apiUrl = "https://api.example.com",
    refreshInterval = 30
}

function on_resume()
    ui:show_text("Loading...")

    http:get(CONFIG.apiUrl, function(data, code)
        if code == 200 then
            local result = json:decode(data)
            ui:show_text("Data: " .. result.value)
        else
            ui:show_text("Error: " .. code)
        end
    end)
end

function on_click()
    on_resume()  -- Refresh on tap
end

function on_long_click()
    ui:show_context_menu({
        "Refresh",
        "Settings",
        "Close"
    }, function(index)
        if index == 0 then
            on_resume()
        end
    end)
end
```

### Deploy to Android

1. Copy your `.lua` file to:
   ```
   /sdcard/Android/data/ru.execbit.aiolauncher/files/
   ```

2. In AIO Launcher:
   - Long press on home screen
   - Select "Add widget" → "Script widget"
   - Choose your script

## Configuration

Each widget has a `CONFIG` table at the top for customization:

```lua
local CONFIG = {
    ip = "192.168.1.1",      -- Device IP
    username = "admin",       -- Username
    password = "password",    -- Password
    useHTTPS = true,         -- Enable HTTPS
    refreshInterval = 60      -- Seconds
}
```

**Security Note**: For production use, consider:
- Using environment variables
- External config files
- API tokens instead of passwords

## Development Tips

1. **Use Mock Data** - Test without hitting real APIs
2. **Check Rate Limits** - Implement throttling for external APIs
3. **Handle Errors** - Wrap API calls with `pcall()`
4. **Cache Results** - Reduce API calls with local caching
5. **Test Interactive Mode** - Verify click handlers work

## Resources

- [AIO Launcher Official](https://aiolauncher.app/)
- [AIO Launcher Scripts](https://github.com/zobnin/aiolauncher_scripts)
- [Lua 5.3 Reference](https://www.lua.org/manual/5.3/)

## License

Apache License 2.0 - See [LICENSE](LICENSE)

## Contributing

1. Fork the repository
2. Create your feature branch
3. Test with the emulator
4. Submit a pull request

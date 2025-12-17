# AIO Launcher Lua Emulator

A local testing environment for AIO Launcher Lua scripts. Test your widgets on your computer before deploying to Android devices.

## Installation

```bash
npm install
```

## Usage

### Basic Usage

```bash
# Run a script
node emulator.js ../Mikrotik/mikrotik_widget_v10.lua

# Run with specific mock data
node emulator.js ../Mikrotik/mikrotik_widget_v10.lua --mock mocks/mikrotik_success.json

# Interactive mode
node emulator.js ../Mikrotik/mikrotik_widget_v10.lua --interactive

# Test specific function
node emulator.js ../Mikrotik/mikrotik_widget_v10.lua --test on_click
```

## Features

- Emulates AIO Launcher APIs (ui, http, json, system)
- Mock HTTP responses for testing
- Interactive mode for simulating user interactions
- Step-through debugging
- Output formatting

## API Emulation

The emulator provides these AIO Launcher APIs:

- `ui:show_text(text)` - Display widget text
- `ui:show_context_menu(items)` - Show context menu
- `http:get(url, callback, headers?)` - HTTP GET request
- `http:post(url, body, callback, headers?)` - HTTP POST request
- `json:decode(data)` - Parse JSON
- `json:encode(table)` - Encode to JSON
- `system:open_browser(url)` - Open browser (logs URL)
- `system:toast(message)` - Show toast notification

## Mock Data

Create JSON files in `mocks/` directory with HTTP response mappings:

```json
{
  "http://10.1.1.1/rest/system/resource": {
    "status": 200,
    "body": {
      "cpu-load": 15,
      "free-memory": 50000000,
      "total-memory": 100000000,
      "uptime": "5d 3h 20m",
      "board-name": "MikroTik",
      "version": "7.15"
    }
  }
}
```


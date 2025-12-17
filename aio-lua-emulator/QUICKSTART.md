# Quick Start Guide

## Installation

```bash
cd aio-lua-emulator
npm install
```

## Basic Usage

### Test the v10 MikroTik script with mocks:

```bash
node emulator.js ../Mikrotik/mikrotik_widget_v10.lua --mock mocks/mikrotik_success.json
```

### Interactive Mode:

```bash
node emulator.js ../Mikrotik/mikrotik_widget_v10.lua --mock mocks/mikrotik_success.json --interactive
```

In interactive mode, you can:
- Run `on_resume()` to refresh the widget
- Simulate `on_click()` to open WebFig
- Simulate `on_long_click()` to show context menu
- Select context menu items

### Test Specific Function:

```bash
node emulator.js ../Mikrotik/mikrotik_widget_v10.lua --test on_click
```

## Creating Mock Data

Create a JSON file in `mocks/` directory:

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

The emulator will match URLs (with or without auth) and return the mock response.

## Tips

- Use `--mock` to test without connecting to real devices
- Use `--interactive` to test user interactions
- Check the console output for HTTP requests and widget display
- Mock files support both authenticated and non-authenticated URLs


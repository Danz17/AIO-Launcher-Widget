# Visual Emulator Guide

## Starting the Visual Emulator

```bash
npm run visual
# or
npm run server
```

Then open your browser to: **http://localhost:3000**

## Features

### 1. Code Editor
- Edit your Lua scripts directly in the browser
- Load scripts from files using the "Load File" button
- Save scripts using the "Save" button

### 2. Widget Preview
- See your widget output in real-time
- Styled to look like AIO Launcher widgets
- Three interaction buttons:
  - **🔄 Resume** - Calls `on_resume()`
  - **👆 Click** - Calls `on_click()`
  - **👆👆 Long Click** - Calls `on_long_click()`

### 3. Mock Data Manager
- Select from existing mock files
- Edit mock data in JSON format
- Create custom mock responses for testing

### 4. HTTP Request Log
- View all HTTP requests made by your script
- See request methods, URLs, and status codes
- Clear log button to reset

## Usage

1. **Write or paste your Lua script** in the code editor
2. **Optionally load mock data** from the dropdown or edit manually
3. **Click "Resume"** to execute `on_resume()`
4. **View the output** in the Widget Preview area
5. **Check HTTP requests** in the log panel

## Example Workflow

1. Start the server: `npm run visual`
2. Open browser to `http://localhost:3000`
3. The sample MikroTik script is pre-loaded
4. Select a mock file (or use the default mock data)
5. Click "Resume" to see the widget output
6. Try "Click" and "Long Click" buttons to test interactions

## Mock Data Format

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

## Tips

- The visual emulator runs scripts server-side for security
- All HTTP requests are logged automatically
- Mock data can be edited on-the-fly without saving
- The widget display updates in real-time after script execution


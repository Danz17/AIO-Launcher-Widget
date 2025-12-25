-- name = "Device Monitor"
-- description = "Battery, WiFi, and device status monitor"
-- author = "Phenix"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local CONFIG = {
  show_battery_details = true,
  show_wifi = true,
  show_brightness = true,
  compact_mode = false
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
local function progress_bar(value, max, width)
  width = width or 10
  if not value or max == 0 then return string.rep("░", width) end
  local pct = math.min(value / max, 1)
  local filled = math.floor(pct * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

local function battery_icon(level, charging)
  if charging then return "⚡" end
  if level >= 80 then return "🔋"
  elseif level >= 50 then return "🔋"
  elseif level >= 20 then return "🪫"
  else return "🪫"
  end
end

local function signal_bars(rssi)
  rssi = tonumber(rssi) or -100
  if rssi >= -50 then return "████"
  elseif rssi >= -60 then return "███░"
  elseif rssi >= -70 then return "██░░"
  elseif rssi >= -80 then return "█░░░"
  else return "░░░░"
  end
end

-- ============================================================================
-- DISPLAY
-- ============================================================================
local function render()
  local lines = {}

  -- Battery section
  local battery = android.getBattery()
  if battery then
    local level = battery.level or 0
    local charging = battery.isCharging or false
    local icon = battery_icon(level, charging)
    local status = charging and "Charging" or "Discharging"

    if CONFIG.compact_mode then
      local compact = string.format("%s %d%%", icon, level)
      if CONFIG.show_brightness then
        local brightness = android.getScreenBrightness() or 0
        compact = compact .. string.format(" │ ☀️ %d%%", brightness)
      end
      ui:show_text(compact)
      return
    end

    table.insert(lines, string.format("%s Battery  %s %d%%",
      icon, progress_bar(level, 100, 8), level))

    if CONFIG.show_battery_details then
      table.insert(lines, string.format("   %s │ %.1f°C",
        status, battery.temperature or 0))
    end
  else
    table.insert(lines, "🔋 Battery: unavailable")
  end

  -- WiFi section
  if CONFIG.show_wifi then
    table.insert(lines, "")
    local ssid = android.getConnectedSSID()
    local signal = android.getWifiSignal()

    if ssid and ssid ~= "" then
      table.insert(lines, string.format("📶 WiFi   %s %sdBm",
        signal_bars(signal), signal or "?"))
      table.insert(lines, "   " .. ssid)
    else
      table.insert(lines, "📶 WiFi: Not connected")
    end
  end

  -- Brightness section
  if CONFIG.show_brightness then
    table.insert(lines, "")
    local brightness = android.getScreenBrightness() or 0
    table.insert(lines, string.format("☀️ Brightness  %s %d%%",
      progress_bar(brightness, 100, 8), brightness))
  end

  -- Device info
  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
  local device = android.getDeviceInfo()
  if device then
    table.insert(lines, string.format("📱 %s", device.model or "Unknown"))
    table.insert(lines, string.format("   Android %s", device.osVersion or "?"))
  end

  ui:show_text(table.concat(lines, "\n"))
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================
function on_resume()
  render()
end

function on_click()
  render()
  system:toast("Refreshed")
end

function on_long_click()
  ui:show_context_menu({
    { "🔄 Refresh", "refresh" },
    { CONFIG.compact_mode and "📊 Full Mode" or "📉 Compact Mode", "toggle" },
    { "━━━━━━━━━━", "" },
    { "⚙️ Settings", "settings" }
  }, "on_menu")
end

function on_menu(idx)
  if idx == 1 then
    render()
  elseif idx == 2 then
    CONFIG.compact_mode = not CONFIG.compact_mode
    render()
  elseif idx == 4 then
    system:open_browser("content://settings")
  end
end

-- Initialize
render()

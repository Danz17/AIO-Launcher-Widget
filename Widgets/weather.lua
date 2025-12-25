-- name = "Weather"
-- description = "Current weather and forecast from OpenWeatherMap"
-- author = "Phenix"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- CONFIGURATION
-- Get free API key at: https://openweathermap.org/api
-- ============================================================================
local CONFIG = {
  api_key = "YOUR_OPENWEATHERMAP_API_KEY",
  city = "Baghdad",
  country = "IQ",
  units = "metric",  -- "metric" (Celsius) or "imperial" (Fahrenheit)
  show_forecast = true,
  show_details = true
}

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
  loading = true,
  error = nil,
  weather = nil,
  forecast = nil
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
local function get_weather_icon(code, is_day)
  -- Weather condition codes: https://openweathermap.org/weather-conditions
  if not code then return "❓" end
  local c = tonumber(code) or 0

  if c >= 200 and c < 300 then return "⛈️"  -- Thunderstorm
  elseif c >= 300 and c < 400 then return "🌧️"  -- Drizzle
  elseif c >= 500 and c < 600 then return "🌧️"  -- Rain
  elseif c >= 600 and c < 700 then return "❄️"  -- Snow
  elseif c >= 700 and c < 800 then return "🌫️"  -- Atmosphere (fog, mist)
  elseif c == 800 then return is_day and "☀️" or "🌙"  -- Clear
  elseif c == 801 then return "🌤️"  -- Few clouds
  elseif c >= 802 and c <= 804 then return "☁️"  -- Clouds
  else return "🌡️"
  end
end

local function get_wind_direction(deg)
  if not deg then return "?" end
  local dirs = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
  local idx = math.floor((deg + 22.5) / 45) % 8 + 1
  return dirs[idx]
end

local function format_time(timestamp, offset)
  if not timestamp then return "?" end
  local t = timestamp + (offset or 0)
  local h = math.floor(t % 86400 / 3600)
  local m = math.floor(t % 3600 / 60)
  return string.format("%02d:%02d", h, m)
end

local function temp_unit()
  return CONFIG.units == "imperial" and "°F" or "°C"
end

local function speed_unit()
  return CONFIG.units == "imperial" and "mph" or "m/s"
end

local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end

-- ============================================================================
-- DISPLAY
-- ============================================================================
local function render()
  if state.loading then
    ui:show_text("⏳ Loading weather for " .. CONFIG.city .. "...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local w = state.weather
  if not w then
    ui:show_text("❌ No weather data")
    return
  end

  local lines = {}
  local now = os.time()
  local is_day = w.sunrise and w.sunset and now > w.sunrise and now < w.sunset

  -- Current weather
  local icon = get_weather_icon(w.condition_id, is_day)
  table.insert(lines, string.format("%s %s", icon, w.description or "Unknown"))
  table.insert(lines, string.format("🌡️ %.0f%s (feels %.0f%s)",
    w.temp or 0, temp_unit(),
    w.feels_like or 0, temp_unit()))

  -- Details
  if CONFIG.show_details then
    table.insert(lines, "")
    table.insert(lines, string.format("💧 Humidity: %d%%", w.humidity or 0))
    table.insert(lines, string.format("💨 Wind: %.1f%s %s",
      w.wind_speed or 0, speed_unit(),
      get_wind_direction(w.wind_deg)))

    if w.sunrise and w.sunset then
      table.insert(lines, string.format("🌅 %s │ 🌇 %s",
        format_time(w.sunrise, w.timezone),
        format_time(w.sunset, w.timezone)))
    end
  end

  -- Forecast
  if CONFIG.show_forecast and state.forecast and #state.forecast > 0 then
    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "📅 Forecast")

    for i, f in ipairs(state.forecast) do
      if i > 3 then break end
      local ficon = get_weather_icon(f.condition_id, true)
      table.insert(lines, string.format("   %s %s: %.0f%s / %.0f%s",
        ficon, f.day or "?",
        f.temp_max or 0, temp_unit(),
        f.temp_min or 0, temp_unit()))
    end
  end

  -- Location
  table.insert(lines, "")
  table.insert(lines, "📍 " .. CONFIG.city .. ", " .. CONFIG.country)

  ui:show_text(table.concat(lines, "\n"))
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================
local function fetch_weather()
  if CONFIG.api_key == "YOUR_OPENWEATHERMAP_API_KEY" then
    state.loading = false
    state.error = "Please set your API key in CONFIG"
    render()
    return
  end

  state.loading = true
  state.error = nil
  render()

  local url = string.format(
    "https://api.openweathermap.org/data/2.5/weather?q=%s,%s&units=%s&appid=%s",
    CONFIG.city, CONFIG.country, CONFIG.units, CONFIG.api_key
  )

  http:get(url, function(body, code)
    if code ~= 200 or not body then
      state.loading = false
      state.error = "Failed to fetch weather (code: " .. tostring(code) .. ")"
      render()
      return
    end

    local data = safe_decode(body)
    if not data then
      state.loading = false
      state.error = "Invalid response"
      render()
      return
    end

    if data.cod and tonumber(data.cod) ~= 200 then
      state.loading = false
      state.error = data.message or "API error"
      render()
      return
    end

    -- Parse current weather
    state.weather = {
      temp = data.main and data.main.temp,
      feels_like = data.main and data.main.feels_like,
      humidity = data.main and data.main.humidity,
      pressure = data.main and data.main.pressure,
      wind_speed = data.wind and data.wind.speed,
      wind_deg = data.wind and data.wind.deg,
      description = data.weather and data.weather[1] and data.weather[1].description,
      condition_id = data.weather and data.weather[1] and data.weather[1].id,
      sunrise = data.sys and data.sys.sunrise,
      sunset = data.sys and data.sys.sunset,
      timezone = data.timezone
    }

    -- Fetch forecast if enabled
    if CONFIG.show_forecast then
      fetch_forecast()
    else
      state.loading = false
      render()
    end
  end)
end

local function fetch_forecast()
  local url = string.format(
    "https://api.openweathermap.org/data/2.5/forecast?q=%s,%s&units=%s&appid=%s",
    CONFIG.city, CONFIG.country, CONFIG.units, CONFIG.api_key
  )

  http:get(url, function(body, code)
    state.loading = false

    if code == 200 and body then
      local data = safe_decode(body)
      if data and data.list then
        -- Group by day and get min/max
        local days = {}
        local day_names = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

        for _, item in ipairs(data.list) do
          local dt = item.dt
          local day_idx = math.floor(dt / 86400)
          local day_name = day_names[tonumber(os.date("%w", dt)) + 1]

          if not days[day_idx] then
            days[day_idx] = {
              day = day_name,
              temp_min = item.main.temp,
              temp_max = item.main.temp,
              condition_id = item.weather and item.weather[1] and item.weather[1].id
            }
          else
            days[day_idx].temp_min = math.min(days[day_idx].temp_min, item.main.temp)
            days[day_idx].temp_max = math.max(days[day_idx].temp_max, item.main.temp)
          end
        end

        -- Convert to array and skip today
        state.forecast = {}
        local today = math.floor(os.time() / 86400)
        for idx, day in pairs(days) do
          if idx > today then
            table.insert(state.forecast, day)
          end
        end

        -- Sort by day index
        table.sort(state.forecast, function(a, b)
          return (a.day or "") < (b.day or "")
        end)
      end
    end

    render()
  end)
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================
function on_resume()
  fetch_weather()
end

function on_click()
  if state.error then
    fetch_weather()
  else
    -- Open weather details in browser
    local url = string.format("https://openweathermap.org/city/%s",
      CONFIG.city)
    system:open_browser(url)
  end
end

function on_long_click()
  ui:show_context_menu({
    { "🔄 Refresh", "refresh" },
    { CONFIG.show_forecast and "📊 Hide Forecast" or "📅 Show Forecast", "forecast" },
    { CONFIG.show_details and "📉 Hide Details" or "📊 Show Details", "details" },
    { "━━━━━━━━━━", "" },
    { "🌐 Open Website", "web" }
  }, "on_menu")
end

function on_menu(idx)
  if idx == 1 then
    fetch_weather()
  elseif idx == 2 then
    CONFIG.show_forecast = not CONFIG.show_forecast
    render()
  elseif idx == 3 then
    CONFIG.show_details = not CONFIG.show_details
    render()
  elseif idx == 5 then
    system:open_browser("https://openweathermap.org")
  end
end

-- Initialize
fetch_weather()

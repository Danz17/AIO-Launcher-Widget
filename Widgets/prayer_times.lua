-- name = "Prayer Times"
-- description = "Islamic prayer times with countdown to next prayer"
-- author = "Phenix"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local CONFIG = {
  city = "Baghdad",
  country = "Iraq",
  method = 3,  -- 1=Univ of Islamic Sciences, 2=ISNA, 3=Muslim World League, 4=Umm Al-Qura
  show_hijri = true,
  show_countdown = true
}

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
  loading = true,
  error = nil,
  timings = nil,
  hijri = nil,
  date = nil
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end

local function time_to_minutes(time_str)
  if not time_str then return 0 end
  local h, m = time_str:match("(%d+):(%d+)")
  if h and m then
    return tonumber(h) * 60 + tonumber(m)
  end
  return 0
end

local function get_current_minutes()
  local t = os.date("*t")
  return t.hour * 60 + t.min
end

local function format_countdown(minutes)
  if minutes < 0 then minutes = minutes + 1440 end
  local h = math.floor(minutes / 60)
  local m = minutes % 60
  if h > 0 then
    return string.format("%dh %dm", h, m)
  else
    return string.format("%dm", m)
  end
end

local function get_next_prayer(timings)
  local prayers = {
    { name = "Fajr", time = timings.Fajr },
    { name = "Dhuhr", time = timings.Dhuhr },
    { name = "Asr", time = timings.Asr },
    { name = "Maghrib", time = timings.Maghrib },
    { name = "Isha", time = timings.Isha }
  }

  local now = get_current_minutes()

  for _, prayer in ipairs(prayers) do
    local prayer_mins = time_to_minutes(prayer.time)
    if prayer_mins > now then
      return prayer.name, prayer_mins - now
    end
  end

  -- After Isha, next is Fajr tomorrow
  local fajr_mins = time_to_minutes(timings.Fajr)
  return "Fajr", (1440 - now) + fajr_mins
end

-- ============================================================================
-- DISPLAY
-- ============================================================================
local function render()
  if state.loading then
    ui:show_text("⏳ Loading prayer times for " .. CONFIG.city .. "...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local t = state.timings
  if not t then
    ui:show_text("❌ No prayer data")
    return
  end

  local lines = {}

  -- Hijri date
  if CONFIG.show_hijri and state.hijri then
    local h = state.hijri
    table.insert(lines, string.format("📅 %s %s %s",
      h.day or "?", h.month and h.month.en or "?", h.year or "?"))
    table.insert(lines, "")
  end

  -- Next prayer countdown
  if CONFIG.show_countdown then
    local next_name, mins_until = get_next_prayer(t)
    table.insert(lines, string.format("⏰ %s in %s", next_name, format_countdown(mins_until)))
    table.insert(lines, "")
  end

  -- Prayer times
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")

  local prayers = {
    { "🌅", "Fajr", t.Fajr },
    { "☀️", "Dhuhr", t.Dhuhr },
    { "🌤️", "Asr", t.Asr },
    { "🌅", "Maghrib", t.Maghrib },
    { "🌙", "Isha", t.Isha }
  }

  local now = get_current_minutes()
  for _, p in ipairs(prayers) do
    local icon, name, time = p[1], p[2], p[3]
    local time_clean = time and time:gsub(" %(.+%)", "") or "?"
    local prayer_mins = time_to_minutes(time_clean)
    local marker = (prayer_mins <= now and prayer_mins + 60 > now) and " ◀" or ""
    table.insert(lines, string.format("%s %-8s %s%s", icon, name, time_clean, marker))
  end

  -- Location
  table.insert(lines, "")
  table.insert(lines, "📍 " .. CONFIG.city .. ", " .. CONFIG.country)

  ui:show_text(table.concat(lines, "\n"))
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================
local function fetch_times()
  state.loading = true
  state.error = nil
  render()

  local url = string.format(
    "http://api.aladhan.com/v1/timingsByCity?city=%s&country=%s&method=%d",
    CONFIG.city, CONFIG.country, CONFIG.method
  )

  http:get(url, function(body, code)
    state.loading = false

    if code ~= 200 or not body then
      state.error = "Failed to fetch times (code: " .. tostring(code) .. ")"
      render()
      return
    end

    local data = safe_decode(body)
    if not data or not data.data then
      state.error = "Invalid response"
      render()
      return
    end

    state.timings = data.data.timings
    state.hijri = data.data.date and data.data.date.hijri
    state.date = data.data.date and data.data.date.gregorian

    render()
  end)
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================
function on_resume()
  fetch_times()
end

function on_click()
  if state.error then
    fetch_times()
  else
    -- Refresh times
    fetch_times()
  end
end

function on_long_click()
  ui:show_context_menu({
    { "🔄 Refresh", "refresh" },
    { CONFIG.show_countdown and "⏰ Hide Countdown" or "⏰ Show Countdown", "countdown" },
    { CONFIG.show_hijri and "📅 Hide Hijri" or "📅 Show Hijri", "hijri" },
    { "━━━━━━━━━━", "" },
    { "🌐 IslamicFinder", "web" }
  }, "on_menu")
end

function on_menu(idx)
  if idx == 1 then
    fetch_times()
  elseif idx == 2 then
    CONFIG.show_countdown = not CONFIG.show_countdown
    render()
  elseif idx == 3 then
    CONFIG.show_hijri = not CONFIG.show_hijri
    render()
  elseif idx == 5 then
    system:open_browser("https://www.islamicfinder.org/prayer-times/")
  end
end

-- Initialize
fetch_times()

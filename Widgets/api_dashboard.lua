-- API Dashboard Widget for AIO Launcher
-- Display data from custom REST API endpoints
-- Uses: http:get(), storage, ui:show_text(), ui:show_chart()

-- Configuration - customize these endpoints
local ENDPOINTS = {
  {
    name = "Bitcoin Price",
    url = "https://api.coindesk.com/v1/bpi/currentprice.json",
    icon = "₿",
    extract = {
      { path = "bpi.USD.rate", label = "USD" },
      { path = "bpi.EUR.rate", label = "EUR" }
    },
    type = "json"
  },
  {
    name = "IP Info",
    url = "https://ipapi.co/json/",
    icon = "🌐",
    extract = {
      { path = "ip", label = "IP" },
      { path = "city", label = "City" },
      { path = "country_name", label = "Country" },
      { path = "org", label = "ISP" }
    },
    type = "json"
  },
  {
    name = "Random Quote",
    url = "https://api.quotable.io/random",
    icon = "💬",
    extract = {
      { path = "content", label = "Quote" },
      { path = "author", label = "Author" }
    },
    type = "json"
  },
  {
    name = "World Time",
    url = "https://worldtimeapi.org/api/ip",
    icon = "🕐",
    extract = {
      { path = "timezone", label = "Timezone" },
      { path = "datetime", label = "Time" },
      { path = "day_of_week", label = "Day" }
    },
    type = "json"
  }
}

local STORAGE_KEY = "api_dashboard_data"
local CONFIG = {
  current_endpoint = 1,
  refresh_minutes = 5,
  max_history = 20
}

-- State
local state = {
  loading = false,
  error = nil,
  data = {},
  last_refresh = 0,
  history = {}  -- for charting numeric values
}

-- Helper functions
local function load_data()
  local data = storage:get(STORAGE_KEY)
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return { current = 1, data = {}, history = {} }
end

local function save_data()
  storage:put(STORAGE_KEY, json.encode({
    current = CONFIG.current_endpoint,
    data = state.data,
    history = state.history,
    last_refresh = state.last_refresh
  }))
end

local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end

local function truncate(str, len)
  if not str then return "" end
  str = tostring(str)
  if #str <= len then return str end
  return str:sub(1, len - 2) .. ".."
end

-- Extract value from JSON using dot-notation path
local function extract_path(obj, path)
  if not obj or not path then return nil end

  local current = obj
  for key in path:gmatch("[^%.]+") do
    if type(current) ~= "table" then
      return nil
    end
    -- Handle array index [n]
    local arr_key = key:match("%[(%d+)%]")
    if arr_key then
      current = current[tonumber(arr_key)]
    else
      current = current[key]
    end
    if current == nil then
      return nil
    end
  end

  return current
end

-- Format value for display
local function format_value(value)
  if value == nil then return "N/A" end
  if type(value) == "table" then return "[object]" end
  if type(value) == "boolean" then return value and "Yes" or "No" end

  local str = tostring(value)

  -- Try to format as number
  local num = tonumber(str:gsub(",", ""))
  if num then
    if num > 1000000 then
      return string.format("%.2fM", num / 1000000)
    elseif num > 1000 then
      return string.format("%.2fK", num / 1000)
    elseif num == math.floor(num) then
      return string.format("%d", num)
    else
      return string.format("%.2f", num)
    end
  end

  -- Format datetime strings
  if str:match("^%d%d%d%d%-%d%d%-%d%dT") then
    local time = str:match("T(%d%d:%d%d)")
    return time or str
  end

  return str
end

-- Display functions
local function render()
  if state.loading then
    local endpoint = ENDPOINTS[CONFIG.current_endpoint]
    ui:show_text("📡 Loading " .. (endpoint and endpoint.name or "API") .. "...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local endpoint = ENDPOINTS[CONFIG.current_endpoint]
  if not endpoint then
    ui:show_text("❌ No endpoint configured")
    return
  end

  local lines = {}

  table.insert(lines, endpoint.icon .. " " .. endpoint.name)
  table.insert(lines, "")

  -- Display extracted values
  if #state.data > 0 then
    for _, item in ipairs(state.data) do
      local value = format_value(item.value)
      table.insert(lines, "📊 " .. item.label .. ":")
      table.insert(lines, "   " .. truncate(value, 28))
    end
  else
    table.insert(lines, "No data available")
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

  -- Footer
  local time_ago = ""
  if state.last_refresh > 0 then
    local elapsed = os.time() - state.last_refresh
    if elapsed < 60 then
      time_ago = elapsed .. "s ago"
    elseif elapsed < 3600 then
      time_ago = math.floor(elapsed / 60) .. "m ago"
    else
      time_ago = math.floor(elapsed / 3600) .. "h ago"
    end
  end

  local endpoint_num = CONFIG.current_endpoint .. "/" .. #ENDPOINTS
  table.insert(lines, "🔄 " .. time_ago .. " | API " .. endpoint_num)

  ui:show_text(table.concat(lines, "\n"))

  -- Show chart if we have numeric history
  if #state.history >= 2 then
    ui:show_chart(state.history, nil, "Value History", true)
  end
end

-- Fetch API data
local function fetch_api()
  local endpoint = ENDPOINTS[CONFIG.current_endpoint]
  if not endpoint then
    state.error = "Invalid endpoint"
    render()
    return
  end

  state.loading = true
  state.error = nil
  render()

  http:get(endpoint.url, function(body, code)
    state.loading = false

    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.data = {}

        -- Extract configured values
        for _, extract in ipairs(endpoint.extract or {}) do
          local value = extract_path(data, extract.path)
          table.insert(state.data, {
            label = extract.label,
            value = value,
            path = extract.path
          })

          -- Track first numeric value for chart
          if #state.data == 1 then
            local num = tonumber(tostring(value):gsub(",", ""))
            if num then
              table.insert(state.history, num)
              if #state.history > CONFIG.max_history then
                table.remove(state.history, 1)
              end
            end
          end
        end

        state.last_refresh = os.time()
        save_data()
      else
        state.error = "Failed to parse JSON"
      end
    else
      state.error = "Request failed (code: " .. tostring(code) .. ")"
    end

    render()
  end)
end

-- Callbacks
function on_resume()
  local saved = load_data()
  CONFIG.current_endpoint = saved.current or 1
  state.data = saved.data or {}
  state.history = saved.history or {}
  state.last_refresh = saved.last_refresh or 0

  -- Check if refresh needed
  local elapsed = os.time() - state.last_refresh
  if elapsed > CONFIG.refresh_minutes * 60 or #state.data == 0 then
    fetch_api()
  else
    render()
  end
end

function on_click()
  if state.error then
    fetch_api()
  else
    -- Cycle to next endpoint
    CONFIG.current_endpoint = (CONFIG.current_endpoint % #ENDPOINTS) + 1
    state.history = {}  -- Reset history for new endpoint
    save_data()
    fetch_api()
  end
end

function on_long_click()
  local menu = {
    "🔄 Refresh",
    "━━━━━━━━━━━━━━━━"
  }

  -- Add endpoint options
  for i, endpoint in ipairs(ENDPOINTS) do
    local check = i == CONFIG.current_endpoint and "✅ " or "⬜ "
    table.insert(menu, check .. endpoint.icon .. " " .. endpoint.name)
  end

  table.insert(menu, "━━━━━━━━━━━━━━━━")
  table.insert(menu, "📈 Clear History")
  table.insert(menu, "📋 Show Raw Data")
  table.insert(menu, "⚙️ Settings")

  ui:show_context_menu(menu)
end

function on_context_menu_click(index)
  if index == 1 then
    fetch_api()
  elseif index >= 3 and index <= 2 + #ENDPOINTS then
    -- Switch endpoint
    CONFIG.current_endpoint = index - 2
    state.history = {}
    save_data()
    fetch_api()
  elseif index == 4 + #ENDPOINTS then
    -- Clear history
    state.history = {}
    save_data()
    system:toast("History cleared")
    render()
  elseif index == 5 + #ENDPOINTS then
    -- Show raw data
    local raw = "📋 Raw API Data\n\n"
    for _, item in ipairs(state.data) do
      raw = raw .. item.label .. ": " .. tostring(item.value) .. "\n"
    end
    raw = raw .. "\nPath expressions:\n"
    local endpoint = ENDPOINTS[CONFIG.current_endpoint]
    if endpoint then
      for _, extract in ipairs(endpoint.extract or {}) do
        raw = raw .. "  " .. extract.path .. "\n"
      end
    end
    ui:show_text(raw)
  elseif index == 6 + #ENDPOINTS then
    -- Settings
    local settings = "⚙️ API Dashboard Settings\n\n"
    settings = settings .. "Refresh: " .. CONFIG.refresh_minutes .. " min\n"
    settings = settings .. "History: " .. CONFIG.max_history .. " points\n\n"
    settings = settings .. "━━━━━━━━━━━━━━━━\n"
    settings = settings .. "Configured APIs:\n"
    for i, ep in ipairs(ENDPOINTS) do
      settings = settings .. i .. ". " .. ep.icon .. " " .. ep.name .. "\n"
      settings = settings .. "   " .. truncate(ep.url, 30) .. "\n"
    end
    settings = settings .. "\nEdit widget code to add APIs"
    ui:show_text(settings)
  end
end

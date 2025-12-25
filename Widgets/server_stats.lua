-- Server Stats Widget for AIO Launcher
-- Monitor remote servers via HTTP status endpoints
-- Uses: http:get(), storage, ui:show_text(), ui:show_chart()

-- Configuration - Add your servers here
local SERVERS = {
  {
    name = "Local Pi-hole",
    icon = "🕳️",
    url = "http://10.1.1.1/admin/api.php?summary",
    type = "pihole",
    extract = {
      { path = "status", label = "Status" },
      { path = "dns_queries_today", label = "Queries" },
      { path = "ads_blocked_today", label = "Blocked" },
      { path = "ads_percentage_today", label = "Block %" }
    }
  },
  {
    name = "Netdata",
    icon = "📊",
    url = "http://localhost:19999/api/v1/info",
    type = "netdata",
    metrics_url = "http://localhost:19999/api/v1/data?chart=system.cpu&points=1",
    extract = {
      { path = "os_name", label = "OS" },
      { path = "os_version", label = "Version" },
      { path = "hostname", label = "Host" }
    }
  },
  {
    name = "Health Check",
    icon = "💚",
    url = "https://httpstat.us/200",
    type = "health",
    expect_code = 200
  },
  {
    name = "Uptime Kuma",
    icon = "📈",
    url = "http://localhost:3001/api/status-page/main",
    type = "uptimekuma",
    extract = {
      { path = "publicGroupList[1].monitorList", label = "Monitors" }
    }
  }
}

local STORAGE_KEY = "server_stats_data"
local CONFIG = {
  current_server = 1,
  refresh_seconds = 60,
  max_history = 30
}

-- State
local state = {
  loading = false,
  error = nil,
  server_status = "unknown",
  metrics = {},
  last_refresh = 0,
  response_time = 0,
  history = {}  -- response times for chart
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
  return { current = 1, history = {} }
end

local function save_data()
  storage:put(STORAGE_KEY, json.encode({
    current = CONFIG.current_server,
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
  for key in path:gmatch("[^%.%[%]]+") do
    if type(current) ~= "table" then
      return nil
    end
    local idx = tonumber(key)
    if idx then
      current = current[idx]
    else
      current = current[key]
    end
    if current == nil then
      return nil
    end
  end

  return current
end

local function format_number(n)
  n = tonumber(n) or 0
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fK", n / 1000)
  else
    return tostring(math.floor(n))
  end
end

local function format_value(value, label)
  if value == nil then return "N/A" end
  if type(value) == "table" then
    -- Count array elements
    if #value > 0 then
      return #value .. " items"
    end
    return "[object]"
  end
  if type(value) == "boolean" then return value and "Yes" or "No" end

  local str = tostring(value)

  -- Format percentages
  if label and label:match("%%") then
    local num = tonumber(str)
    if num then
      return string.format("%.1f%%", num)
    end
  end

  -- Format large numbers
  local num = tonumber(str)
  if num and num > 1000 then
    return format_number(num)
  end

  return str
end

local function get_status_icon(status)
  if status == "online" or status == "enabled" or status == "up" then
    return "✅"
  elseif status == "offline" or status == "disabled" or status == "down" then
    return "❌"
  elseif status == "warning" or status == "degraded" then
    return "⚠️"
  else
    return "❓"
  end
end

-- Display functions
local function render()
  if state.loading then
    local server = SERVERS[CONFIG.current_server]
    ui:show_text("📡 Checking " .. (server and server.name or "server") .. "...")
    return
  end

  local server = SERVERS[CONFIG.current_server]
  if not server then
    ui:show_text("❌ No server configured")
    return
  end

  local lines = {}

  -- Header
  local status_icon = get_status_icon(state.server_status)
  table.insert(lines, server.icon .. " " .. server.name)
  table.insert(lines, status_icon .. " Status: " .. state.server_status)
  table.insert(lines, "")

  if state.error then
    table.insert(lines, "❌ Error:")
    table.insert(lines, "   " .. truncate(state.error, 28))
  else
    -- Display metrics
    for _, metric in ipairs(state.metrics) do
      local value = format_value(metric.value, metric.label)
      table.insert(lines, "📊 " .. metric.label .. ": " .. truncate(value, 20))
    end

    -- Response time
    if state.response_time > 0 then
      table.insert(lines, "")
      table.insert(lines, "⏱️ Response: " .. state.response_time .. "ms")
    end
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

  local server_num = CONFIG.current_server .. "/" .. #SERVERS
  table.insert(lines, "🔄 " .. time_ago .. " | Server " .. server_num)

  ui:show_text(table.concat(lines, "\n"))

  -- Show response time chart
  if #state.history >= 2 then
    ui:show_chart(state.history, nil, "Response Time (ms)", true)
  end
end

-- Check server
local function check_server()
  local server = SERVERS[CONFIG.current_server]
  if not server then
    state.error = "Invalid server"
    render()
    return
  end

  state.loading = true
  state.error = nil
  render()

  local start_time = os.time() * 1000  -- Approximate ms

  http:get(server.url, function(body, code)
    state.loading = false
    state.response_time = (os.time() * 1000) - start_time

    -- Track response time
    table.insert(state.history, state.response_time > 0 and state.response_time or 1)
    if #state.history > CONFIG.max_history then
      table.remove(state.history, 1)
    end

    if server.type == "health" then
      -- Simple health check
      if code == (server.expect_code or 200) then
        state.server_status = "online"
        state.metrics = {
          { label = "HTTP Code", value = code },
          { label = "Response", value = "OK" }
        }
      else
        state.server_status = "offline"
        state.error = "Expected " .. (server.expect_code or 200) .. ", got " .. tostring(code)
      end
    elseif code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.server_status = "online"
        state.metrics = {}

        -- Extract configured values
        for _, extract in ipairs(server.extract or {}) do
          local value = extract_path(data, extract.path)
          table.insert(state.metrics, {
            label = extract.label,
            value = value
          })

          -- Check for status field
          if extract.path == "status" and value then
            local val = tostring(value):lower()
            if val == "enabled" or val == "ok" or val == "running" then
              state.server_status = "online"
            elseif val == "disabled" or val == "error" then
              state.server_status = "offline"
            end
          end
        end
      else
        state.server_status = "online"
        state.metrics = {
          { label = "Response", value = "Non-JSON data" }
        }
      end
    else
      state.server_status = "offline"
      state.error = "Request failed (code: " .. tostring(code) .. ")"
    end

    state.last_refresh = os.time()
    save_data()
    render()
  end)
end

-- Callbacks
function on_resume()
  local saved = load_data()
  CONFIG.current_server = saved.current or 1
  state.history = saved.history or {}

  check_server()
end

function on_click()
  if state.loading then
    system:toast("Check in progress...")
    return
  end

  -- Cycle to next server
  CONFIG.current_server = (CONFIG.current_server % #SERVERS) + 1
  state.history = {}  -- Reset history for new server
  save_data()
  check_server()
end

function on_long_click()
  local menu = {
    "🔄 Refresh",
    "━━━━━━━━━━━━━━━━"
  }

  -- Add server options
  for i, server in ipairs(SERVERS) do
    local check = i == CONFIG.current_server and "✅ " or "⬜ "
    local status = ""
    if i == CONFIG.current_server then
      status = " [" .. state.server_status .. "]"
    end
    table.insert(menu, check .. server.icon .. " " .. server.name .. status)
  end

  table.insert(menu, "━━━━━━━━━━━━━━━━")
  table.insert(menu, "📈 Clear History")
  table.insert(menu, "🌐 Open in Browser")
  table.insert(menu, "⚙️ Settings")

  ui:show_context_menu(menu)
end

function on_context_menu_click(index)
  if index == 1 then
    check_server()
  elseif index >= 3 and index <= 2 + #SERVERS then
    -- Switch server
    CONFIG.current_server = index - 2
    state.history = {}
    save_data()
    check_server()
  elseif index == 4 + #SERVERS then
    -- Clear history
    state.history = {}
    save_data()
    system:toast("History cleared")
    render()
  elseif index == 5 + #SERVERS then
    -- Open in browser
    local server = SERVERS[CONFIG.current_server]
    if server then
      system:open_browser(server.url)
    end
  elseif index == 6 + #SERVERS then
    -- Settings
    local settings = "⚙️ Server Stats Settings\n\n"
    settings = settings .. "Refresh: " .. CONFIG.refresh_seconds .. " sec\n"
    settings = settings .. "History: " .. CONFIG.max_history .. " points\n\n"
    settings = settings .. "━━━━━━━━━━━━━━━━\n"
    settings = settings .. "Configured Servers:\n\n"
    for i, server in ipairs(SERVERS) do
      settings = settings .. i .. ". " .. server.icon .. " " .. server.name .. "\n"
      settings = settings .. "   Type: " .. server.type .. "\n"
      settings = settings .. "   " .. truncate(server.url, 28) .. "\n\n"
    end
    settings = settings .. "Edit widget code to add servers"
    ui:show_text(settings)
  end
end

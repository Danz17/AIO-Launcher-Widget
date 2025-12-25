-- MikroTik Log Viewer Widget for AIO Launcher
-- View system logs with filtering by topic
-- Uses: http:get(), ui:show_text()

-- Configuration
local CONFIG = {
  ip = "10.1.1.1",
  user = "admin",
  pass = "admin123",
  max_entries = 12,
  current_filter = "all"  -- all, firewall, dhcp, ppp, wireless, system, error
}

-- State
local state = {
  loading = true,
  error = nil,
  logs = {},
  filtered_logs = {}
}

-- Topic icons and colors
local TOPIC_ICONS = {
  firewall = "🔥",
  dhcp = "🔌",
  ppp = "📡",
  wireless = "📶",
  system = "⚙️",
  info = "ℹ️",
  warning = "⚠️",
  error = "❌",
  critical = "🚨",
  script = "📜",
  hotspot = "🌐",
  interface = "🔗",
  account = "👤",
  caps = "📻",
  default = "📋"
}

-- Helper functions
local function get_url(endpoint)
  return string.format("http://%s:%s@%s%s",
    CONFIG.user, CONFIG.pass, CONFIG.ip, endpoint)
end

local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end

local function get_icon(topics)
  if not topics then return TOPIC_ICONS.default end

  -- Check for severity first
  if topics:match("error") then return TOPIC_ICONS.error end
  if topics:match("critical") then return TOPIC_ICONS.critical end
  if topics:match("warning") then return TOPIC_ICONS.warning end

  -- Then check for topic type
  if topics:match("firewall") then return TOPIC_ICONS.firewall end
  if topics:match("dhcp") then return TOPIC_ICONS.dhcp end
  if topics:match("ppp") then return TOPIC_ICONS.ppp end
  if topics:match("wireless") then return TOPIC_ICONS.wireless end
  if topics:match("system") then return TOPIC_ICONS.system end
  if topics:match("script") then return TOPIC_ICONS.script end
  if topics:match("hotspot") then return TOPIC_ICONS.hotspot end
  if topics:match("interface") then return TOPIC_ICONS.interface end
  if topics:match("account") then return TOPIC_ICONS.account end
  if topics:match("caps") then return TOPIC_ICONS.caps end
  if topics:match("info") then return TOPIC_ICONS.info end

  return TOPIC_ICONS.default
end

local function truncate(str, len)
  if not str then return "" end
  if #str <= len then return str end
  return str:sub(1, len - 2) .. ".."
end

local function format_time(time_str)
  if not time_str then return "" end
  -- Extract just HH:MM:SS from time string
  local time = time_str:match("(%d+:%d+:%d+)")
  return time or time_str
end

local function matches_filter(log_entry, filter)
  if filter == "all" then return true end

  local topics = log_entry.topics or ""

  if filter == "error" then
    return topics:match("error") or topics:match("critical") or topics:match("warning")
  end

  return topics:match(filter)
end

local function apply_filter()
  state.filtered_logs = {}
  for _, log in ipairs(state.logs) do
    if matches_filter(log, CONFIG.current_filter) then
      table.insert(state.filtered_logs, log)
    end
  end
end

-- Display functions
local function render()
  if state.loading then
    ui:show_text("📋 Loading logs...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local lines = {}

  -- Header with filter indicator
  local filter_name = CONFIG.current_filter == "all" and "All Logs" or
                      (get_icon(CONFIG.current_filter) .. " " .. CONFIG.current_filter:gsub("^%l", string.upper))
  table.insert(lines, "📋 MikroTik Logs")
  table.insert(lines, "🔍 Filter: " .. filter_name)
  table.insert(lines, "")

  if #state.filtered_logs == 0 then
    table.insert(lines, "No log entries found")
    table.insert(lines, "for current filter")
  else
    -- Show logs in reverse order (newest first)
    local shown = 0
    for i = #state.filtered_logs, 1, -1 do
      if shown >= CONFIG.max_entries then
        table.insert(lines, string.format("   ... +%d more entries", #state.filtered_logs - shown))
        break
      end

      local log = state.filtered_logs[i]
      local icon = get_icon(log.topics)
      local time = format_time(log.time)
      local msg = log.message or ""

      -- Format message
      msg = truncate(msg, 28)

      table.insert(lines, string.format("%s %s", icon, time))
      table.insert(lines, "   " .. msg)
      shown = shown + 1
    end
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

  -- Stats
  local error_count = 0
  local warning_count = 0
  for _, log in ipairs(state.logs) do
    local topics = log.topics or ""
    if topics:match("error") or topics:match("critical") then
      error_count = error_count + 1
    elseif topics:match("warning") then
      warning_count = warning_count + 1
    end
  end

  table.insert(lines, string.format("📊 Total: %d | ⚠️ %d | ❌ %d",
    #state.logs, warning_count, error_count))

  ui:show_text(table.concat(lines, "\n"))
end

-- Fetch logs
local function fetch_logs()
  state.loading = true
  state.error = nil
  render()

  http:get(get_url("/rest/log"), function(body, code)
    state.loading = false

    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.logs = data
        apply_filter()
      else
        state.error = "Failed to parse logs"
      end
    else
      state.error = "Connection failed (code: " .. tostring(code) .. ")"
    end

    render()
  end)
end

-- Callbacks
function on_resume()
  fetch_logs()
end

function on_click()
  if state.error then
    fetch_logs()
  else
    -- Cycle through filters
    local filters = { "all", "firewall", "dhcp", "ppp", "wireless", "system", "error" }
    local current_idx = 1
    for i, f in ipairs(filters) do
      if f == CONFIG.current_filter then
        current_idx = i
        break
      end
    end
    current_idx = (current_idx % #filters) + 1
    CONFIG.current_filter = filters[current_idx]
    apply_filter()
    render()
  end
end

function on_long_click()
  ui:show_context_menu({
    "🔄 Refresh",
    "━━━━━━━━━━━━━━━━",
    "📋 All Logs",
    "🔥 Firewall Logs",
    "🔌 DHCP Logs",
    "📡 PPP Logs",
    "📶 Wireless Logs",
    "⚙️ System Logs",
    "❌ Errors Only",
    "━━━━━━━━━━━━━━━━",
    "🗑️ Clear Logs on Router",
    "🌐 Open WebFig Logs"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    fetch_logs()
  elseif index == 3 then
    CONFIG.current_filter = "all"
    apply_filter()
    render()
  elseif index == 4 then
    CONFIG.current_filter = "firewall"
    apply_filter()
    render()
  elseif index == 5 then
    CONFIG.current_filter = "dhcp"
    apply_filter()
    render()
  elseif index == 6 then
    CONFIG.current_filter = "ppp"
    apply_filter()
    render()
  elseif index == 7 then
    CONFIG.current_filter = "wireless"
    apply_filter()
    render()
  elseif index == 8 then
    CONFIG.current_filter = "system"
    apply_filter()
    render()
  elseif index == 9 then
    CONFIG.current_filter = "error"
    apply_filter()
    render()
  elseif index == 11 then
    -- Clear logs
    local url = get_url("/rest/log/print")
    http:post(url .. "?remove=true", "{}", { "Content-Type: application/json" }, function(res, code)
      if code == 200 then
        system:toast("Logs cleared")
        fetch_logs()
      else
        system:toast("Failed to clear logs")
      end
    end)
  elseif index == 12 then
    system:open_browser("http://" .. CONFIG.ip .. "/webfig/#Log")
  end
end

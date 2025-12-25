-- name = "Pi-hole Monitor"
-- description = "DNS blocking statistics from Pi-hole"
-- author = "Phenix"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local CONFIG = {
  ip = "192.168.1.100",  -- Pi-hole IP address
  api_token = "",        -- Optional: for enable/disable (Settings > API > Show API token)
  show_top_blocked = true,
  show_top_clients = false
}

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
  loading = true,
  error = nil,
  stats = nil,
  top_blocked = nil
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
local function format_number(n)
  if not n then return "0" end
  n = tonumber(n) or 0
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fK", n / 1000)
  else
    return tostring(math.floor(n))
  end
end

local function progress_bar(value, max, width)
  width = width or 10
  if not value or max == 0 then return string.rep("░", width) end
  local pct = math.min(value / max, 1)
  local filled = math.floor(pct * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
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
    ui:show_text("⏳ Connecting to Pi-hole at " .. CONFIG.ip .. "...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local s = state.stats
  if not s then
    ui:show_text("❌ No data from Pi-hole")
    return
  end

  local lines = {}

  -- Status indicator
  local status_icon = s.status == "enabled" and "🟢" or "🔴"
  local status_text = s.status == "enabled" and "Blocking Active" or "Blocking Disabled"
  table.insert(lines, status_icon .. " " .. status_text)
  table.insert(lines, "")

  -- Query stats
  local total = tonumber(s.dns_queries_today) or 0
  local blocked = tonumber(s.ads_blocked_today) or 0
  local pct = tonumber(s.ads_percentage_today) or 0

  table.insert(lines, "📊 Queries Today")
  table.insert(lines, string.format("   Total: %s │ Blocked: %s",
    format_number(total), format_number(blocked)))
  table.insert(lines, string.format("   %s %.1f%%",
    progress_bar(pct, 100, 12), pct))

  -- Domains and clients
  table.insert(lines, "")
  table.insert(lines, string.format("🌐 Domains: %s │ 👥 Clients: %s",
    format_number(s.domains_being_blocked),
    format_number(s.unique_clients)))

  -- Top blocked domain
  if CONFIG.show_top_blocked and state.top_blocked then
    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "🚫 Top Blocked")
    local count = 0
    for domain, hits in pairs(state.top_blocked) do
      if count >= 3 then break end
      local short = #domain > 25 and domain:sub(1, 22) .. "..." or domain
      table.insert(lines, string.format("   %s (%s)", short, format_number(hits)))
      count = count + 1
    end
  end

  ui:show_text(table.concat(lines, "\n"))
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================
local function fetch_stats()
  state.loading = true
  state.error = nil
  render()

  local url = "http://" .. CONFIG.ip .. "/admin/api.php?summary"

  http:get(url, function(body, code)
    if code ~= 200 or not body then
      state.loading = false
      state.error = "Connection failed (code: " .. tostring(code) .. ")"
      render()
      return
    end

    local data = safe_decode(body)
    if not data then
      state.loading = false
      state.error = "Invalid response from Pi-hole"
      render()
      return
    end

    state.stats = data

    -- Fetch top blocked if enabled
    if CONFIG.show_top_blocked then
      fetch_top_blocked()
    else
      state.loading = false
      render()
    end
  end)
end

local function fetch_top_blocked()
  local url = "http://" .. CONFIG.ip .. "/admin/api.php?topItems=3"

  if CONFIG.api_token and CONFIG.api_token ~= "" then
    url = url .. "&auth=" .. CONFIG.api_token
  end

  http:get(url, function(body, code)
    state.loading = false

    if code == 200 and body then
      local data = safe_decode(body)
      if data and data.top_ads then
        state.top_blocked = data.top_ads
      end
    end

    render()
  end)
end

local function toggle_blocking()
  if not CONFIG.api_token or CONFIG.api_token == "" then
    system:toast("API token required for this action")
    return
  end

  local action = state.stats and state.stats.status == "enabled" and "disable" or "enable"
  local url = string.format("http://%s/admin/api.php?%s&auth=%s",
    CONFIG.ip, action, CONFIG.api_token)

  http:get(url, function(body, code)
    if code == 200 then
      system:toast("Pi-hole " .. action .. "d")
      fetch_stats()
    else
      system:toast("Failed to " .. action .. " Pi-hole")
    end
  end)
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================
function on_resume()
  fetch_stats()
end

function on_click()
  if state.error then
    fetch_stats()
  else
    system:open_browser("http://" .. CONFIG.ip .. "/admin")
  end
end

function on_long_click()
  local toggle_text = state.stats and state.stats.status == "enabled"
    and "🔴 Disable Blocking" or "🟢 Enable Blocking"

  ui:show_context_menu({
    { "🔄 Refresh", "refresh" },
    { toggle_text, "toggle" },
    { "━━━━━━━━━━", "" },
    { "🌐 Open Admin", "admin" }
  }, "on_menu")
end

function on_menu(idx)
  if idx == 1 then
    fetch_stats()
  elseif idx == 2 then
    toggle_blocking()
  elseif idx == 4 then
    system:open_browser("http://" .. CONFIG.ip .. "/admin")
  end
end

-- Initialize
fetch_stats()

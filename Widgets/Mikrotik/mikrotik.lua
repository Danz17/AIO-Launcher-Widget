-- name = "MikroTik Monitor"
-- description = "Comprehensive MikroTik router monitoring with LTE, clients, and remote control"
-- author = "Phenix"
-- version = "2.0"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- CONFIGURATION - Edit these values for your router
-- ============================================================================
local CONFIG = {
  ip = "10.1.1.1",
  user = "admin",
  pass = "admin123",

  -- Display options
  show_lte = true,
  show_clients = true,
  max_clients = 5,
  compact_mode = false,

  -- Data limits (GB) for progress bars
  daily_limit = 10,
  monthly_limit = 100
}

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
  loading = true,
  error = nil,
  system = nil,
  lte = nil,
  clients = {},
  pending = 0
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
local function get_url(endpoint)
  return string.format("http://%s:%s@%s%s",
    CONFIG.user, CONFIG.pass, CONFIG.ip, endpoint)
end

local function format_bytes(bytes)
  if not bytes then return "0B" end
  bytes = tonumber(bytes) or 0
  if bytes >= 1073741824 then
    return string.format("%.1fGB", bytes / 1073741824)
  elseif bytes >= 1048576 then
    return string.format("%.1fMB", bytes / 1048576)
  elseif bytes >= 1024 then
    return string.format("%.1fKB", bytes / 1024)
  else
    return string.format("%dB", bytes)
  end
end

local function parse_uptime(str)
  if not str then return 0 end
  local seconds = 0
  for value, unit in string.gmatch(str, "(%d+)(%a)") do
    local v = tonumber(value) or 0
    if unit == "w" then seconds = seconds + v * 604800
    elseif unit == "d" then seconds = seconds + v * 86400
    elseif unit == "h" then seconds = seconds + v * 3600
    elseif unit == "m" then seconds = seconds + v * 60
    elseif unit == "s" then seconds = seconds + v
    end
  end
  return seconds
end

local function format_uptime(seconds)
  if not seconds or seconds == 0 then return "0m" end
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  if days > 0 then
    return string.format("%dd %dh", days, hours)
  elseif hours > 0 then
    return string.format("%dh %dm", hours, mins)
  else
    return string.format("%dm", mins)
  end
end

local function progress_bar(value, max, width)
  width = width or 10
  if max == 0 then max = 1 end
  local pct = math.min(value / max, 1)
  local filled = math.floor(pct * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

local function signal_bars(rssi)
  rssi = tonumber(rssi) or -100
  if rssi > -65 then return "████", "excellent"
  elseif rssi > -75 then return "███░", "good"
  elseif rssi > -85 then return "██░░", "fair"
  elseif rssi > -95 then return "█░░░", "weak"
  else return "░░░░", "none"
  end
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
    ui:show_text("⏳ Connecting to " .. CONFIG.ip .. "...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local lines = {}
  local s = state.system

  if not s then
    ui:show_text("❌ No data received")
    return
  end

  -- Compact mode: single line
  if CONFIG.compact_mode then
    local cpu = s.cpu or 0
    local ram = s.ram or 0
    local text = string.format("🖥 %d%% │ 💾 %d%% │ ⏱ %s",
      cpu, ram, format_uptime(s.uptime))
    if state.lte then
      local bars = signal_bars(state.lte.rssi)
      text = text .. " │ 📡 " .. bars
    end
    ui:show_text(text)
    return
  end

  -- Full mode
  -- Header
  table.insert(lines, "📟 " .. (s.board or "MikroTik"))
  table.insert(lines, "🔧 RouterOS " .. (s.version or "?"))
  table.insert(lines, "")

  -- System stats
  local cpu = s.cpu or 0
  local ram = s.ram or 0
  table.insert(lines, string.format("🖥 CPU  %s %d%%", progress_bar(cpu, 100, 8), cpu))
  table.insert(lines, string.format("💾 RAM  %s %d%%", progress_bar(ram, 100, 8), ram))
  table.insert(lines, "⏱ Uptime: " .. format_uptime(s.uptime))

  -- LTE info (if enabled and available)
  if CONFIG.show_lte and state.lte then
    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
    local lte = state.lte
    local bars, quality = signal_bars(lte.rssi)
    table.insert(lines, string.format("📡 LTE  %s  %sdBm (%s)",
      bars, lte.rssi or "?", quality))
    if lte.operator then
      table.insert(lines, "   " .. lte.operator)
    end
    if lte.band then
      table.insert(lines, "   Band " .. lte.band)
    end
  end

  -- Hotspot clients (if enabled and available)
  if CONFIG.show_clients and #state.clients > 0 then
    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "👥 Clients (" .. #state.clients .. ")")

    -- Sort by bytes-out descending
    table.sort(state.clients, function(a, b)
      return (tonumber(a["bytes-out"]) or 0) > (tonumber(b["bytes-out"]) or 0)
    end)

    local shown = 0
    for _, client in ipairs(state.clients) do
      if shown >= CONFIG.max_clients then break end
      local name = client.user or client.address or "unknown"
      local bytes = tonumber(client["bytes-out"]) or 0
      table.insert(lines, string.format("   • %s  %s", name, format_bytes(bytes)))
      shown = shown + 1
    end

    if #state.clients > CONFIG.max_clients then
      table.insert(lines, string.format("   ... +%d more", #state.clients - CONFIG.max_clients))
    end
  end

  ui:show_text(table.concat(lines, "\n"))
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================
local function fetch_all()
  state.loading = true
  state.error = nil
  state.pending = 1
  render()

  -- Fetch system resources
  http:get(get_url("/rest/system/resource"), function(body, code)
    if code ~= 200 or not body then
      state.loading = false
      state.error = "Connection failed (code: " .. tostring(code) .. ")"
      render()
      return
    end

    local data = safe_decode(body)
    if not data then
      state.loading = false
      state.error = "Invalid JSON response"
      render()
      return
    end

    -- Parse system data
    local total_mem = tonumber(data["total-memory"]) or 1
    local free_mem = tonumber(data["free-memory"]) or 0
    local ram_pct = math.floor(((total_mem - free_mem) / total_mem) * 100)

    state.system = {
      board = data["board-name"],
      version = data["version"],
      uptime = parse_uptime(data["uptime"]),
      cpu = tonumber(data["cpu-load"]) or 0,
      ram = ram_pct,
      arch = data["architecture-name"]
    }

    -- Now fetch LTE if enabled
    if CONFIG.show_lte then
      state.pending = state.pending + 1
      http:get(get_url("/rest/interface/lte"), function(lte_body, lte_code)
        state.pending = state.pending - 1
        if lte_code == 200 and lte_body then
          local lte_list = safe_decode(lte_body)
          if lte_list and #lte_list > 0 then
            local lte_name = lte_list[1].name
            -- Get LTE info
            http:get(get_url("/rest/interface/lte/info?=numbers=" .. lte_name), function(info_body, info_code)
              if info_code == 200 and info_body then
                local info = safe_decode(info_body)
                if info and #info > 0 then
                  state.lte = {
                    rssi = info[1].rssi or info[1]["signal-strength"],
                    rsrp = info[1].rsrp,
                    rsrq = info[1].rsrq,
                    sinr = info[1].sinr,
                    operator = info[1].operator,
                    band = info[1]["current-band"] or info[1]["primary-band"]
                  }
                end
              end
              check_done()
            end)
          else
            check_done()
          end
        else
          check_done()
        end
      end)
    end

    -- Fetch hotspot clients if enabled
    if CONFIG.show_clients then
      state.pending = state.pending + 1
      http:get(get_url("/rest/ip/hotspot/active"), function(hs_body, hs_code)
        state.pending = state.pending - 1
        if hs_code == 200 and hs_body then
          local clients = safe_decode(hs_body)
          if clients then
            state.clients = clients
          end
        end
        check_done()
      end)
    end

    check_done()
  end)
end

function check_done()
  state.pending = state.pending - 1
  if state.pending <= 0 then
    state.loading = false
    render()
  end
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================
function on_resume()
  fetch_all()
end

function on_click()
  if state.error then
    fetch_all()
  else
    system:open_browser("http://" .. CONFIG.ip)
  end
end

function on_long_click()
  ui:show_context_menu({
    { "🔄 Refresh", "refresh" },
    { CONFIG.compact_mode and "📊 Full Mode" or "📉 Compact Mode", "toggle_mode" },
    { "━━━━━━━━━━━━", "" },
    { "📡 Toggle LTE", "toggle_lte" },
    { "👥 Toggle Hotspot", "toggle_hotspot" },
    { "🔄 Reboot Router", "reboot" },
    { "━━━━━━━━━━━━", "" },
    { "🌐 Open WebFig", "webfig" }
  }, "on_menu_select")
end

function on_menu_select(idx)
  local actions = {
    [1] = function() fetch_all() end,
    [2] = function()
      CONFIG.compact_mode = not CONFIG.compact_mode
      render()
    end,
    [4] = function() toggle_interface("lte1") end,
    [5] = function() toggle_interface("hotspot1") end,
    [6] = function() reboot_router() end,
    [8] = function() system:open_browser("http://" .. CONFIG.ip) end
  }
  if actions[idx] then actions[idx]() end
end

-- ============================================================================
-- REMOTE CONTROL
-- ============================================================================
function toggle_interface(iface)
  local url = get_url("/rest/interface/" .. iface)
  http:get(url, function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        local disabled = data.disabled == "true" or data.disabled == true
        local action = disabled and "enable" or "disable"
        local post_url = get_url("/rest/interface/" .. action)
        http:post(post_url, json.encode({ numbers = iface }), function(res, res_code)
          if res_code == 200 then
            system:toast(iface .. " " .. action .. "d")
            fetch_all()
          else
            system:toast("Failed to " .. action .. " " .. iface)
          end
        end)
      end
    end
  end)
end

function reboot_router()
  local url = get_url("/rest/system/reboot")
  http:post(url, "{}", function(body, code)
    if code == 200 then
      system:toast("Router rebooting...")
    else
      system:toast("Reboot failed (code: " .. tostring(code) .. ")")
    end
  end)
end

-- ============================================================================
-- INITIALIZE
-- ============================================================================
fetch_all()

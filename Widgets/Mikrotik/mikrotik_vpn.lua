-- MikroTik VPN Status Widget for AIO Launcher
-- Monitor VPN connections (L2TP, PPTP, SSTP, IPsec, WireGuard)
-- Uses: http:get(), http:post(), ui:show_text()

-- Configuration
local CONFIG = {
  ip = "10.1.1.1",
  user = "admin",
  pass = "admin123",
  max_connections = 8
}

-- State
local state = {
  loading = true,
  error = nil,
  ppp_active = {},      -- Active PPP connections (L2TP, PPTP, SSTP)
  l2tp_server = {},     -- L2TP server status
  pptp_server = {},     -- PPTP server status
  sstp_server = {},     -- SSTP server status
  ipsec_peers = {},     -- IPsec active peers
  wireguard = {},       -- WireGuard peers
  view_mode = "active"  -- active, servers, ipsec
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

local function format_bytes(bytes)
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

local function format_uptime(str)
  if not str then return "?" end
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

local function truncate(str, len)
  if not str then return "" end
  if #str <= len then return str end
  return str:sub(1, len - 2) .. ".."
end

local function get_vpn_icon(service)
  if service:match("l2tp") then return "🔐"
  elseif service:match("pptp") then return "🔒"
  elseif service:match("sstp") then return "🔏"
  elseif service:match("ovpn") then return "🛡️"
  else return "📡" end
end

-- Display functions
local function render()
  if state.loading then
    ui:show_text("🔐 Loading VPN status...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local lines = {}

  if state.view_mode == "active" then
    -- Active VPN Connections
    table.insert(lines, "🔐 Active VPN Connections")
    table.insert(lines, "")

    if #state.ppp_active == 0 then
      table.insert(lines, "No active VPN connections")
    else
      local shown = 0
      for _, conn in ipairs(state.ppp_active) do
        if shown >= CONFIG.max_connections then
          table.insert(lines, string.format("   ... +%d more", #state.ppp_active - shown))
          break
        end

        local icon = get_vpn_icon(conn.service or "")
        local name = conn.name or "unknown"
        local address = conn.address or "?"
        local uptime = format_uptime(conn.uptime)
        local service = conn.service or "ppp"

        table.insert(lines, string.format("%s %s", icon, truncate(name, 16)))
        table.insert(lines, string.format("   %s [%s]", address, service))
        table.insert(lines, string.format("   ⏱️ %s", uptime))

        -- Traffic stats
        local bytes_in = format_bytes(conn["bytes-in"])
        local bytes_out = format_bytes(conn["bytes-out"])
        table.insert(lines, string.format("   ↓%s ↑%s", bytes_in, bytes_out))
        table.insert(lines, "")

        shown = shown + 1
      end
    end

  elseif state.view_mode == "servers" then
    -- VPN Server Status
    table.insert(lines, "🖥️ VPN Server Status")
    table.insert(lines, "")

    -- L2TP Server
    local l2tp = state.l2tp_server[1]
    if l2tp then
      local enabled = not (l2tp.disabled == "true" or l2tp.disabled == true)
      local icon = enabled and "✅" or "⬜"
      table.insert(lines, icon .. " L2TP Server")
      if enabled then
        table.insert(lines, "   Auth: " .. (l2tp["use-ipsec"] == "yes" and "IPsec" or "mschap2"))
      end
    end

    -- PPTP Server
    local pptp = state.pptp_server[1]
    if pptp then
      local enabled = not (pptp.disabled == "true" or pptp.disabled == true)
      local icon = enabled and "✅" or "⬜"
      table.insert(lines, icon .. " PPTP Server")
      if enabled then
        table.insert(lines, "   Auth: " .. (pptp.authentication or "mschap2"))
      end
    end

    -- SSTP Server
    local sstp = state.sstp_server[1]
    if sstp then
      local enabled = not (sstp.disabled == "true" or sstp.disabled == true)
      local icon = enabled and "✅" or "⬜"
      table.insert(lines, icon .. " SSTP Server")
      if enabled then
        table.insert(lines, "   Port: " .. (sstp.port or "443"))
      end
    end

    if not l2tp and not pptp and not sstp then
      table.insert(lines, "No VPN servers configured")
    end

  else
    -- IPsec / WireGuard View
    table.insert(lines, "🛡️ IPsec & WireGuard")
    table.insert(lines, "")

    -- IPsec Peers
    if #state.ipsec_peers > 0 then
      table.insert(lines, "📡 IPsec Active Peers:")
      local shown = 0
      for _, peer in ipairs(state.ipsec_peers) do
        if shown >= 4 then break end
        local remote = peer["remote-address"] or "?"
        local state_str = peer.state or "?"
        local icon = state_str == "established" and "✅" or "⏳"
        table.insert(lines, string.format("   %s %s", icon, remote))
        shown = shown + 1
      end
    else
      table.insert(lines, "📡 No active IPsec peers")
    end

    table.insert(lines, "")

    -- WireGuard Peers
    if #state.wireguard > 0 then
      table.insert(lines, "🔗 WireGuard Interfaces:")
      for _, wg in ipairs(state.wireguard) do
        local name = wg.name or "wg0"
        local disabled = wg.disabled == "true" or wg.disabled == true
        local icon = disabled and "⬜" or "✅"
        local public_key = truncate(wg["public-key"] or "?", 12)
        table.insert(lines, string.format("   %s %s", icon, name))
      end
    else
      table.insert(lines, "🔗 No WireGuard configured")
    end
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

  -- Summary
  table.insert(lines, string.format("📊 Active: %d | IPsec: %d | WG: %d",
    #state.ppp_active, #state.ipsec_peers, #state.wireguard))

  ui:show_text(table.concat(lines, "\n"))
end

-- Fetch VPN data
local function fetch_all()
  state.loading = true
  state.error = nil
  render()

  local pending = 6

  local function check_done()
    pending = pending - 1
    if pending <= 0 then
      state.loading = false
      render()
    end
  end

  -- Fetch active PPP connections
  http:get(get_url("/rest/ppp/active"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.ppp_active = data
      end
    else
      state.error = "Connection failed"
    end
    check_done()
  end)

  -- Fetch L2TP server
  http:get(get_url("/rest/interface/l2tp-server/server"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.l2tp_server = type(data) == "table" and (data[1] and data or {data}) or {}
      end
    end
    check_done()
  end)

  -- Fetch PPTP server
  http:get(get_url("/rest/interface/pptp-server/server"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.pptp_server = type(data) == "table" and (data[1] and data or {data}) or {}
      end
    end
    check_done()
  end)

  -- Fetch SSTP server
  http:get(get_url("/rest/interface/sstp-server/server"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.sstp_server = type(data) == "table" and (data[1] and data or {data}) or {}
      end
    end
    check_done()
  end)

  -- Fetch IPsec active peers
  http:get(get_url("/rest/ip/ipsec/active-peers"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.ipsec_peers = data
      end
    end
    check_done()
  end)

  -- Fetch WireGuard interfaces
  http:get(get_url("/rest/interface/wireguard"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.wireguard = data
      end
    end
    check_done()
  end)
end

-- Disconnect a VPN user
local function disconnect_user(conn_id)
  local url = get_url("/rest/ppp/active/" .. conn_id)
  http:get(url, function(body, code)
    if code == 200 then
      -- Use remove method
      local remove_url = get_url("/rest/ppp/active/remove")
      http:post(remove_url, json.encode({ ".id" = conn_id }), { "Content-Type: application/json" }, function(res, res_code)
        if res_code == 200 then
          system:toast("User disconnected")
          fetch_all()
        else
          system:toast("Failed to disconnect")
        end
      end)
    end
  end)
end

-- Toggle VPN server
local function toggle_server(server_type)
  local endpoints = {
    l2tp = "/rest/interface/l2tp-server/server",
    pptp = "/rest/interface/pptp-server/server",
    sstp = "/rest/interface/sstp-server/server"
  }

  local endpoint = endpoints[server_type]
  if not endpoint then return end

  local url = get_url(endpoint)
  http:get(url, function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        local server = type(data) == "table" and (data[1] or data) or data
        local disabled = server.enabled == "no" or server.enabled == false
        local action = disabled and "yes" or "no"

        http:post(url, json.encode({ enabled = action }), { "Content-Type: application/json" }, function(res, res_code)
          if res_code == 200 or res_code == 201 then
            system:toast(server_type:upper() .. " server " .. (disabled and "enabled" or "disabled"))
            fetch_all()
          else
            system:toast("Failed to toggle " .. server_type)
          end
        end)
      end
    end
  end)
end

-- Callbacks
function on_resume()
  fetch_all()
end

function on_click()
  if state.error then
    fetch_all()
  else
    -- Cycle through views
    if state.view_mode == "active" then
      state.view_mode = "servers"
    elseif state.view_mode == "servers" then
      state.view_mode = "ipsec"
    else
      state.view_mode = "active"
    end
    render()
  end
end

function on_long_click()
  ui:show_context_menu({
    "🔄 Refresh",
    "━━━━━━━━━━━━━━━━",
    "📡 Active Connections",
    "🖥️ Server Status",
    "🛡️ IPsec & WireGuard",
    "━━━━━━━━━━━━━━━━",
    "🔐 Toggle L2TP Server",
    "🔒 Toggle PPTP Server",
    "🔏 Toggle SSTP Server",
    "━━━━━━━━━━━━━━━━",
    "🌐 Open WebFig VPN"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    fetch_all()
  elseif index == 3 then
    state.view_mode = "active"
    render()
  elseif index == 4 then
    state.view_mode = "servers"
    render()
  elseif index == 5 then
    state.view_mode = "ipsec"
    render()
  elseif index == 7 then
    toggle_server("l2tp")
  elseif index == 8 then
    toggle_server("pptp")
  elseif index == 9 then
    toggle_server("sstp")
  elseif index == 11 then
    system:open_browser("http://" .. CONFIG.ip .. "/webfig/#PPP")
  end
end

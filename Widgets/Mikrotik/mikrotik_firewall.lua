-- MikroTik Firewall Monitor Widget for AIO Launcher
-- Monitor firewall rules, hit counts, and quick enable/disable
-- Uses: http:get(), http:post(), ui:show_text(), storage

-- Configuration
local CONFIG = {
  ip = "10.1.1.1",
  user = "admin",
  pass = "admin123",
  max_rules = 8,
  show_disabled = false
}

-- State
local state = {
  loading = true,
  error = nil,
  filter_rules = {},
  nat_rules = {},
  address_list = {},
  view_mode = "filter"  -- filter, nat, address
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

local function format_number(n)
  n = tonumber(n) or 0
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fK", n / 1000)
  else
    return tostring(n)
  end
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

local function truncate(str, len)
  if not str then return "" end
  if #str <= len then return str end
  return str:sub(1, len - 2) .. ".."
end

-- Display functions
local function render()
  if state.loading then
    ui:show_text("🔥 Loading firewall rules...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local lines = {}

  if state.view_mode == "filter" then
    -- Filter Rules View
    table.insert(lines, "🔥 Firewall Filter Rules")
    table.insert(lines, "")

    if #state.filter_rules == 0 then
      table.insert(lines, "No filter rules found")
    else
      local shown = 0
      for i, rule in ipairs(state.filter_rules) do
        if shown >= CONFIG.max_rules then
          table.insert(lines, string.format("   ... +%d more rules", #state.filter_rules - shown))
          break
        end

        local disabled = rule.disabled == "true" or rule.disabled == true
        if CONFIG.show_disabled or not disabled then
          local icon = disabled and "⬜" or (rule.action == "drop" and "🛑" or
                       rule.action == "accept" and "✅" or
                       rule.action == "reject" and "⛔" or "📋")
          local chain = rule.chain or "?"
          local comment = rule.comment or rule.action or "unnamed"
          local packets = format_number(rule.packets)
          local bytes = format_bytes(rule.bytes)

          table.insert(lines, string.format("%s %s", icon, truncate(comment, 18)))
          table.insert(lines, string.format("   [%s] %s pkts %s", chain, packets, bytes))
          shown = shown + 1
        end
      end
    end

  elseif state.view_mode == "nat" then
    -- NAT Rules View
    table.insert(lines, "🔄 NAT Rules")
    table.insert(lines, "")

    if #state.nat_rules == 0 then
      table.insert(lines, "No NAT rules found")
    else
      local shown = 0
      for i, rule in ipairs(state.nat_rules) do
        if shown >= CONFIG.max_rules then
          table.insert(lines, string.format("   ... +%d more rules", #state.nat_rules - shown))
          break
        end

        local disabled = rule.disabled == "true" or rule.disabled == true
        if CONFIG.show_disabled or not disabled then
          local icon = disabled and "⬜" or (rule.action == "masquerade" and "🎭" or
                       rule.action == "dst-nat" and "➡️" or
                       rule.action == "src-nat" and "⬅️" or "📋")
          local chain = rule.chain or "?"
          local comment = rule.comment or rule.action or "unnamed"
          local packets = format_number(rule.packets)

          table.insert(lines, string.format("%s %s", icon, truncate(comment, 18)))
          table.insert(lines, string.format("   [%s] %s pkts", chain, packets))
          shown = shown + 1
        end
      end
    end

  else
    -- Address List View
    table.insert(lines, "📋 Address Lists")
    table.insert(lines, "")

    if #state.address_list == 0 then
      table.insert(lines, "No address list entries")
    else
      -- Group by list name
      local lists = {}
      for _, entry in ipairs(state.address_list) do
        local list = entry.list or "unknown"
        lists[list] = (lists[list] or 0) + 1
      end

      for list, count in pairs(lists) do
        table.insert(lines, string.format("📌 %s: %d entries", list, count))
      end

      table.insert(lines, "")
      table.insert(lines, "Recent entries:")
      local shown = 0
      for i = #state.address_list, 1, -1 do
        if shown >= 5 then break end
        local entry = state.address_list[i]
        table.insert(lines, string.format("   %s [%s]", entry.address or "?", entry.list or "?"))
        shown = shown + 1
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

  local total_filter = #state.filter_rules
  local total_nat = #state.nat_rules
  local total_addr = #state.address_list
  table.insert(lines, string.format("📊 Filter: %d | NAT: %d | Addr: %d", total_filter, total_nat, total_addr))

  ui:show_text(table.concat(lines, "\n"))
end

-- Fetch firewall data
local function fetch_all()
  state.loading = true
  state.error = nil
  render()

  local pending = 3

  local function check_done()
    pending = pending - 1
    if pending <= 0 then
      state.loading = false
      render()
    end
  end

  -- Fetch filter rules
  http:get(get_url("/rest/ip/firewall/filter"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.filter_rules = data
      end
    end
    check_done()
  end)

  -- Fetch NAT rules
  http:get(get_url("/rest/ip/firewall/nat"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.nat_rules = data
      end
    end
    check_done()
  end)

  -- Fetch address lists
  http:get(get_url("/rest/ip/firewall/address-list"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.address_list = data
      end
    else
      state.error = "Connection failed"
    end
    check_done()
  end)
end

-- Toggle rule enabled/disabled
local function toggle_rule(rule_type, rule_id)
  local endpoint = rule_type == "nat" and "/rest/ip/firewall/nat/" or "/rest/ip/firewall/filter/"
  local url = get_url(endpoint .. rule_id)

  http:get(url, function(body, code)
    if code == 200 and body then
      local rule = safe_decode(body)
      if rule then
        local disabled = rule.disabled == "true" or rule.disabled == true
        local action = disabled and "false" or "true"
        local patch_url = url
        local patch_body = json.encode({ disabled = action })

        http:post(patch_url, patch_body, { "Content-Type: application/json" }, function(res, res_code)
          if res_code == 200 or res_code == 201 then
            system:toast("Rule " .. (disabled and "enabled" or "disabled"))
            fetch_all()
          else
            system:toast("Failed to toggle rule")
          end
        end)
      end
    end
  end)
end

-- Add IP to address list
local function add_to_list(ip, list_name)
  local url = get_url("/rest/ip/firewall/address-list")
  local body = json.encode({
    address = ip,
    list = list_name,
    comment = "Added via AIO Widget"
  })

  http:post(url, body, { "Content-Type: application/json" }, function(res, code)
    if code == 200 or code == 201 then
      system:toast("Added " .. ip .. " to " .. list_name)
      fetch_all()
    else
      system:toast("Failed to add address")
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
    if state.view_mode == "filter" then
      state.view_mode = "nat"
    elseif state.view_mode == "nat" then
      state.view_mode = "address"
    else
      state.view_mode = "filter"
    end
    render()
  end
end

function on_long_click()
  ui:show_context_menu({
    "🔄 Refresh",
    "━━━━━━━━━━━━━━━━",
    "🔥 View Filter Rules",
    "🔄 View NAT Rules",
    "📋 View Address Lists",
    "━━━━━━━━━━━━━━━━",
    CONFIG.show_disabled and "👁️ Hide Disabled" or "👁️ Show Disabled",
    "🚫 Block IP (clipboard)",
    "✅ Whitelist IP (clipboard)",
    "━━━━━━━━━━━━━━━━",
    "🌐 Open WebFig"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    fetch_all()
  elseif index == 3 then
    state.view_mode = "filter"
    render()
  elseif index == 4 then
    state.view_mode = "nat"
    render()
  elseif index == 5 then
    state.view_mode = "address"
    render()
  elseif index == 7 then
    CONFIG.show_disabled = not CONFIG.show_disabled
    render()
  elseif index == 8 then
    local ip = system:clipboard()
    if ip and ip:match("^%d+%.%d+%.%d+%.%d+") then
      add_to_list(ip, "blocked")
      system:toast("Blocking " .. ip)
    else
      system:toast("No valid IP in clipboard")
    end
  elseif index == 9 then
    local ip = system:clipboard()
    if ip and ip:match("^%d+%.%d+%.%d+%.%d+") then
      add_to_list(ip, "whitelist")
      system:toast("Whitelisting " .. ip)
    else
      system:toast("No valid IP in clipboard")
    end
  elseif index == 11 then
    system:open_browser("http://" .. CONFIG.ip .. "/webfig/#IP:Firewall")
  end
end

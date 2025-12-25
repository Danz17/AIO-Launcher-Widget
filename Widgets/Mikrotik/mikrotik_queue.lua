-- MikroTik Queue Monitor Widget for AIO Launcher
-- Monitor bandwidth queues, limits, and real-time usage
-- Uses: http:get(), ui:show_text(), ui:show_chart()

-- Configuration
local CONFIG = {
  ip = "10.1.1.1",
  user = "admin",
  pass = "admin123",
  max_queues = 8,
  show_disabled = false,
  refresh_interval = 5  -- seconds (for background refresh)
}

-- State
local state = {
  loading = true,
  error = nil,
  simple_queues = {},
  queue_tree = {},
  view_mode = "simple",  -- simple, tree
  history = {}  -- for chart
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
    return string.format("%.1fG", bytes / 1073741824)
  elseif bytes >= 1048576 then
    return string.format("%.1fM", bytes / 1048576)
  elseif bytes >= 1024 then
    return string.format("%.1fK", bytes / 1024)
  else
    return string.format("%dB", bytes)
  end
end

local function format_rate(rate)
  if not rate or rate == "" or rate == "0" then return "∞" end
  local num = tonumber(rate:match("(%d+)"))
  if not num then return rate end

  if rate:match("G") then
    return string.format("%.1fGbps", num)
  elseif rate:match("M") then
    return string.format("%dMbps", num)
  elseif rate:match("k") or rate:match("K") then
    return string.format("%dKbps", num)
  else
    return string.format("%dbps", num)
  end
end

local function parse_rate_bps(rate)
  if not rate or rate == "" or rate == "0" then return 0 end
  local num = tonumber(rate:match("(%d+)"))
  if not num then return 0 end

  if rate:match("G") then return num * 1000000000
  elseif rate:match("M") then return num * 1000000
  elseif rate:match("k") or rate:match("K") then return num * 1000
  else return num end
end

local function progress_bar(value, max, width)
  width = width or 10
  if not max or max == 0 then return string.rep("░", width) end
  local pct = math.min(value / max, 1)
  local filled = math.floor(pct * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

local function truncate(str, len)
  if not str then return "" end
  if #str <= len then return str end
  return str:sub(1, len - 2) .. ".."
end

-- Display functions
local function render()
  if state.loading then
    ui:show_text("📊 Loading queue data...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local lines = {}

  if state.view_mode == "simple" then
    -- Simple Queues View
    table.insert(lines, "📊 Simple Queues")
    table.insert(lines, "")

    if #state.simple_queues == 0 then
      table.insert(lines, "No simple queues found")
    else
      local shown = 0
      for i, queue in ipairs(state.simple_queues) do
        if shown >= CONFIG.max_queues then
          table.insert(lines, string.format("   ... +%d more", #state.simple_queues - shown))
          break
        end

        local disabled = queue.disabled == "true" or queue.disabled == true
        if CONFIG.show_disabled or not disabled then
          local icon = disabled and "⬜" or "📦"
          local name = queue.name or queue.target or "unnamed"
          local target = queue.target or "?"

          -- Parse limits
          local max_limit = queue["max-limit"] or ""
          local up_limit, down_limit = "∞", "∞"
          if max_limit and max_limit ~= "" then
            local parts = {}
            for part in max_limit:gmatch("[^/]+") do
              table.insert(parts, part)
            end
            if #parts >= 2 then
              up_limit = format_rate(parts[1])
              down_limit = format_rate(parts[2])
            end
          end

          -- Traffic stats
          local bytes = format_bytes(queue.bytes)
          local packets = queue.packets or "0"

          table.insert(lines, string.format("%s %s", icon, truncate(name, 16)))
          table.insert(lines, string.format("   ↑%s ↓%s", up_limit, down_limit))

          -- Show current rate if available
          local rate = queue.rate or ""
          if rate ~= "" then
            local parts = {}
            for part in rate:gmatch("[^/]+") do
              table.insert(parts, part)
            end
            if #parts >= 2 then
              local up_rate = format_bytes(parts[1]) .. "/s"
              local down_rate = format_bytes(parts[2]) .. "/s"
              table.insert(lines, string.format("   📈 ↑%s ↓%s", up_rate, down_rate))
            end
          end

          shown = shown + 1
        end
      end
    end

  else
    -- Queue Tree View
    table.insert(lines, "🌳 Queue Tree")
    table.insert(lines, "")

    if #state.queue_tree == 0 then
      table.insert(lines, "No queue tree entries")
    else
      local shown = 0
      -- Group by parent
      local parents = {}
      for _, q in ipairs(state.queue_tree) do
        local parent = q.parent or "global"
        if not parents[parent] then
          parents[parent] = {}
        end
        table.insert(parents[parent], q)
      end

      for parent, children in pairs(parents) do
        if shown >= CONFIG.max_queues then break end
        table.insert(lines, "📁 " .. parent)

        for _, queue in ipairs(children) do
          if shown >= CONFIG.max_queues then break end

          local disabled = queue.disabled == "true" or queue.disabled == true
          if CONFIG.show_disabled or not disabled then
            local name = queue.name or "unnamed"
            local max_limit = format_rate(queue["max-limit"])
            local priority = queue.priority or "8"

            table.insert(lines, string.format("   └ %s [P%s] %s",
              truncate(name, 12), priority, max_limit))
            shown = shown + 1
          end
        end
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

  -- Summary
  local active_simple = 0
  for _, q in ipairs(state.simple_queues) do
    if not (q.disabled == "true" or q.disabled == true) then
      active_simple = active_simple + 1
    end
  end

  local active_tree = 0
  for _, q in ipairs(state.queue_tree) do
    if not (q.disabled == "true" or q.disabled == true) then
      active_tree = active_tree + 1
    end
  end

  table.insert(lines, string.format("📊 Simple: %d | Tree: %d active", active_simple, active_tree))

  ui:show_text(table.concat(lines, "\n"))

  -- Show chart with history if we have data
  if #state.history >= 2 then
    ui:show_chart(state.history, nil, "Total Throughput", true)
  end
end

-- Calculate total throughput for chart
local function get_total_throughput()
  local total = 0
  for _, queue in ipairs(state.simple_queues) do
    local rate = queue.rate or ""
    for part in rate:gmatch("[^/]+") do
      local num = tonumber(part) or 0
      total = total + num
    end
  end
  return total / 1000000  -- Convert to Mbps
end

-- Fetch queue data
local function fetch_all()
  state.loading = true
  state.error = nil
  render()

  local pending = 2

  local function check_done()
    pending = pending - 1
    if pending <= 0 then
      state.loading = false
      -- Update history for chart
      local throughput = get_total_throughput()
      table.insert(state.history, throughput)
      if #state.history > 20 then
        table.remove(state.history, 1)
      end
      render()
    end
  end

  -- Fetch simple queues
  http:get(get_url("/rest/queue/simple"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.simple_queues = data
      end
    else
      state.error = "Connection failed"
    end
    check_done()
  end)

  -- Fetch queue tree
  http:get(get_url("/rest/queue/tree"), function(body, code)
    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.queue_tree = data
      end
    end
    check_done()
  end)
end

-- Toggle queue enabled/disabled
local function toggle_queue(queue_type, queue_id)
  local endpoint = queue_type == "tree" and "/rest/queue/tree/" or "/rest/queue/simple/"
  local url = get_url(endpoint .. queue_id)

  http:get(url, function(body, code)
    if code == 200 and body then
      local queue = safe_decode(body)
      if queue then
        local disabled = queue.disabled == "true" or queue.disabled == true
        local action = disabled and "false" or "true"
        local patch_body = json.encode({ disabled = action })

        http:post(url, patch_body, { "Content-Type: application/json" }, function(res, res_code)
          if res_code == 200 or res_code == 201 then
            system:toast("Queue " .. (disabled and "enabled" or "disabled"))
            fetch_all()
          else
            system:toast("Failed to toggle queue")
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
    -- Toggle view mode
    if state.view_mode == "simple" then
      state.view_mode = "tree"
    else
      state.view_mode = "simple"
    end
    render()
  end
end

function on_long_click()
  ui:show_context_menu({
    "🔄 Refresh",
    "━━━━━━━━━━━━━━━━",
    "📊 View Simple Queues",
    "🌳 View Queue Tree",
    "━━━━━━━━━━━━━━━━",
    CONFIG.show_disabled and "👁️ Hide Disabled" or "👁️ Show Disabled",
    "📈 Clear Chart History",
    "━━━━━━━━━━━━━━━━",
    "🌐 Open WebFig Queues"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    fetch_all()
  elseif index == 3 then
    state.view_mode = "simple"
    render()
  elseif index == 4 then
    state.view_mode = "tree"
    render()
  elseif index == 6 then
    CONFIG.show_disabled = not CONFIG.show_disabled
    render()
  elseif index == 7 then
    state.history = {}
    system:toast("Chart history cleared")
    render()
  elseif index == 9 then
    system:open_browser("http://" .. CONFIG.ip .. "/webfig/#Queues")
  end
end

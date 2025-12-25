-- name = "Speed Test"
-- description = "Internet speed test using Cloudflare"
-- author = "Phenix"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local CONFIG = {
  download_size = 1000000,  -- 1MB download test
  upload_size = 100000,     -- 100KB upload test
  max_history = 5,
  show_history = true
}

-- Storage key
local KEY_HISTORY = "speedtest_history"

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
  testing = false,
  download_speed = nil,
  upload_speed = nil,
  ping = nil,
  last_test = nil,
  error = nil
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

local function format_speed(mbps)
  if not mbps then return "?" end
  if mbps >= 100 then
    return string.format("%.0f", mbps)
  elseif mbps >= 10 then
    return string.format("%.1f", mbps)
  else
    return string.format("%.2f", mbps)
  end
end

local function get_history()
  local data = storage:get(KEY_HISTORY)
  return safe_decode(data) or {}
end

local function save_result(download, upload, ping)
  local history = get_history()

  table.insert(history, 1, {
    download = download,
    upload = upload,
    ping = ping,
    time = os.time()
  })

  while #history > CONFIG.max_history do
    table.remove(history)
  end

  storage:put(KEY_HISTORY, json.encode(history))
end

local function format_time(timestamp)
  if not timestamp then return "" end
  local diff = os.time() - timestamp
  if diff < 60 then return "just now"
  elseif diff < 3600 then return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then return math.floor(diff / 3600) .. "h ago"
  else return math.floor(diff / 86400) .. "d ago"
  end
end

local function speed_bar(speed, max_speed)
  max_speed = max_speed or 100
  local width = 10
  local filled = math.min(math.floor((speed / max_speed) * width), width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

-- ============================================================================
-- DISPLAY
-- ============================================================================
local function render()
  local lines = {}

  table.insert(lines, "🚀 Speed Test")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")

  if state.testing then
    table.insert(lines, "")
    table.insert(lines, "⏳ Testing speed...")
    table.insert(lines, "")
    table.insert(lines, "Please wait...")
    ui:show_text(table.concat(lines, "\n"))
    return
  end

  if state.error then
    table.insert(lines, "")
    table.insert(lines, "❌ " .. state.error)
    table.insert(lines, "")
    table.insert(lines, "Tap to retry")
    ui:show_text(table.concat(lines, "\n"))
    return
  end

  if state.download_speed then
    table.insert(lines, "")
    table.insert(lines, string.format("⬇️ Download  %s  %s Mbps",
      speed_bar(state.download_speed, 100),
      format_speed(state.download_speed)))

    if state.upload_speed then
      table.insert(lines, string.format("⬆️ Upload    %s  %s Mbps",
        speed_bar(state.upload_speed, 50),
        format_speed(state.upload_speed)))
    end

    if state.ping then
      table.insert(lines, string.format("📡 Ping      %d ms", state.ping))
    end

    if state.last_test then
      table.insert(lines, "")
      table.insert(lines, "⏰ " .. format_time(state.last_test))
    end
  else
    table.insert(lines, "")
    table.insert(lines, "No test results yet")
    table.insert(lines, "")
    table.insert(lines, "Tap to run speed test")
  end

  -- History
  if CONFIG.show_history then
    local history = get_history()
    if #history > 1 then
      table.insert(lines, "")
      table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
      table.insert(lines, "📊 History")
      for i = 2, math.min(#history, 4) do
        local h = history[i]
        table.insert(lines, string.format("   %s: ↓%s ↑%s",
          format_time(h.time),
          format_speed(h.download),
          format_speed(h.upload)))
      end
    end
  end

  ui:show_text(table.concat(lines, "\n"))
end

-- ============================================================================
-- SPEED TEST
-- ============================================================================
local test_start_time = 0

local function run_test()
  state.testing = true
  state.error = nil
  state.download_speed = nil
  state.upload_speed = nil
  state.ping = nil
  render()

  -- Test download speed using Cloudflare
  local download_url = string.format(
    "https://speed.cloudflare.com/__down?bytes=%d",
    CONFIG.download_size
  )

  test_start_time = os.time()
  local start_ms = os.clock() * 1000

  http:get(download_url, function(body, code)
    local end_ms = os.clock() * 1000
    local duration_s = (end_ms - start_ms) / 1000

    if code == 200 and body then
      local bytes = #body
      local mbps = (bytes * 8) / (duration_s * 1000000)
      state.download_speed = mbps

      -- Estimate ping (very rough)
      state.ping = math.floor(duration_s * 100)  -- Rough estimate

      -- Save result
      state.last_test = os.time()
      save_result(state.download_speed, state.upload_speed, state.ping)
    else
      state.error = "Download test failed (code: " .. tostring(code) .. ")"
    end

    state.testing = false
    render()
  end)
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================
function on_resume()
  -- Load last result from history
  local history = get_history()
  if #history > 0 then
    state.download_speed = history[1].download
    state.upload_speed = history[1].upload
    state.ping = history[1].ping
    state.last_test = history[1].time
  end
  render()
end

function on_click()
  if state.testing then
    system:toast("Test in progress...")
    return
  end

  run_test()
end

function on_long_click()
  ui:show_context_menu({
    { "🚀 Run Test", "test" },
    { "🗑️ Clear History", "clear" },
    { CONFIG.show_history and "📊 Hide History" or "📊 Show History", "history" },
    { "━━━━━━━━━━", "" },
    { "🌐 Speedtest.net", "web" }
  }, "on_menu")
end

function on_menu(idx)
  if idx == 1 then
    run_test()
  elseif idx == 2 then
    storage:delete(KEY_HISTORY)
    state.download_speed = nil
    state.upload_speed = nil
    state.ping = nil
    state.last_test = nil
    system:toast("History cleared")
    render()
  elseif idx == 3 then
    CONFIG.show_history = not CONFIG.show_history
    render()
  elseif idx == 5 then
    system:open_browser("https://www.speedtest.net")
  end
end

-- Initialize
on_resume()

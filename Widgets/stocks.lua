-- name = "Stock Ticker"
-- description = "Real-time stock prices from Yahoo Finance"
-- author = "Phenix"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local CONFIG = {
  symbols = {"AAPL", "GOOGL", "MSFT", "TSLA"},
  show_change = true,
  show_volume = false,
  compact_mode = false
}

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
  loading = true,
  error = nil,
  stocks = {},
  pending = 0
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

local function format_price(price)
  if not price then return "?" end
  if price >= 1000 then
    return string.format("%.0f", price)
  elseif price >= 100 then
    return string.format("%.1f", price)
  else
    return string.format("%.2f", price)
  end
end

local function format_volume(vol)
  if not vol then return "?" end
  if vol >= 1000000000 then
    return string.format("%.1fB", vol / 1000000000)
  elseif vol >= 1000000 then
    return string.format("%.1fM", vol / 1000000)
  elseif vol >= 1000 then
    return string.format("%.1fK", vol / 1000)
  else
    return tostring(vol)
  end
end

local function change_indicator(change_pct)
  if not change_pct then return "━" end
  if change_pct > 0 then return "▲"
  elseif change_pct < 0 then return "▼"
  else return "━"
  end
end

local function sparkline(prices)
  if not prices or #prices < 2 then return "" end
  local min, max = prices[1], prices[1]
  for _, p in ipairs(prices) do
    if p < min then min = p end
    if p > max then max = p end
  end
  local range = max - min
  if range == 0 then return string.rep("▅", #prices) end

  local chars = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
  local result = ""
  for _, p in ipairs(prices) do
    local idx = math.floor((p - min) / range * 7) + 1
    result = result .. chars[idx]
  end
  return result
end

-- ============================================================================
-- DISPLAY
-- ============================================================================
local function render()
  if state.loading then
    ui:show_text("⏳ Loading stock prices...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  if #state.stocks == 0 then
    ui:show_text("❌ No stock data")
    return
  end

  local lines = {}

  -- Header
  table.insert(lines, "📈 Stock Ticker")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")

  for _, stock in ipairs(state.stocks) do
    local indicator = change_indicator(stock.change_pct)
    local sign = stock.change_pct and stock.change_pct >= 0 and "+" or ""

    if CONFIG.compact_mode then
      table.insert(lines, string.format("%s %s $%s %s%s%%",
        stock.symbol,
        indicator,
        format_price(stock.price),
        sign,
        stock.change_pct and string.format("%.1f", stock.change_pct) or "?"
      ))
    else
      table.insert(lines, "")
      table.insert(lines, string.format("%s %s", indicator, stock.symbol))
      table.insert(lines, string.format("   $%s  %s%s%%",
        format_price(stock.price),
        sign,
        stock.change_pct and string.format("%.2f", stock.change_pct) or "?"
      ))

      if CONFIG.show_volume and stock.volume then
        table.insert(lines, string.format("   Vol: %s", format_volume(stock.volume)))
      end
    end
  end

  -- Market status hint
  local hour = tonumber(os.date("%H"))
  local is_market_hours = hour >= 14 and hour < 21  -- US market hours (UTC)
  table.insert(lines, "")
  table.insert(lines, is_market_hours and "🟢 Market Open" or "🔴 Market Closed")

  ui:show_text(table.concat(lines, "\n"))
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================
local function fetch_stock(symbol)
  local url = string.format(
    "https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=1d&range=1d",
    symbol
  )

  http:get(url, function(body, code)
    state.pending = state.pending - 1

    if code == 200 and body then
      local data = safe_decode(body)
      if data and data.chart and data.chart.result and data.chart.result[1] then
        local result = data.chart.result[1]
        local meta = result.meta
        local quote = result.indicators and result.indicators.quote and result.indicators.quote[1]

        local stock = {
          symbol = symbol,
          price = meta and meta.regularMarketPrice,
          prev_close = meta and meta.previousClose,
          volume = meta and meta.regularMarketVolume
        }

        if stock.price and stock.prev_close then
          stock.change = stock.price - stock.prev_close
          stock.change_pct = (stock.change / stock.prev_close) * 100
        end

        -- Find or update in state
        local found = false
        for i, s in ipairs(state.stocks) do
          if s.symbol == symbol then
            state.stocks[i] = stock
            found = true
            break
          end
        end
        if not found then
          table.insert(state.stocks, stock)
        end
      end
    end

    if state.pending <= 0 then
      state.loading = false
      render()
    end
  end)
end

local function fetch_all()
  state.loading = true
  state.error = nil
  state.stocks = {}
  state.pending = #CONFIG.symbols
  render()

  for _, symbol in ipairs(CONFIG.symbols) do
    fetch_stock(symbol)
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
    fetch_all()
    system:toast("Refreshing...")
  end
end

function on_long_click()
  ui:show_context_menu({
    { "🔄 Refresh", "refresh" },
    { CONFIG.compact_mode and "📊 Full Mode" or "📉 Compact Mode", "mode" },
    { CONFIG.show_volume and "📈 Hide Volume" or "📊 Show Volume", "volume" },
    { "━━━━━━━━━━", "" },
    { "🌐 Yahoo Finance", "web" }
  }, "on_menu")
end

function on_menu(idx)
  if idx == 1 then
    fetch_all()
  elseif idx == 2 then
    CONFIG.compact_mode = not CONFIG.compact_mode
    render()
  elseif idx == 3 then
    CONFIG.show_volume = not CONFIG.show_volume
    render()
  elseif idx == 5 then
    system:open_browser("https://finance.yahoo.com")
  end
end

-- Initialize
fetch_all()

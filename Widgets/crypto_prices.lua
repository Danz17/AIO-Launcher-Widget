-- name = "Crypto Prices"
-- description = "Cryptocurrency price tracker (Binance)"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    symbols = {"BTCUSDT", "ETHUSDT", "BNBUSDT"},
    showGraphs = true,
    graphHistory = 20,
    alerts = {}  -- Price alerts: {symbol = {above = price, below = price}}
}

-- State
local state = {
    tickers = {},
    priceHistory = {},
    alertTriggered = {},
    error = nil
}

-- UTILITY FUNCTIONS

local function fmtPrice(price)
    if not price then return "0.00" end
    local num = tonumber(price)
    if not num then return "0.00" end
    if num >= 1000 then return string.format("%.2f", num) end
    if num >= 1 then return string.format("%.4f", num) end
    if num >= 0.01 then return string.format("%.6f", num) end
    return string.format("%.8f", num)
end

local function fmtPercent(percent)
    if not percent then return "0.00%" end
    local num = tonumber(percent)
    if not num then return "0.00%" end
    local sign = num >= 0 and "+" or ""
    return string.format("%s%.2f%%", sign, num)
end

local function fmtVolume(volume)
    if not volume then return "0" end
    local num = tonumber(volume)
    if not num then return "0" end
    if num >= 1e9 then return string.format("%.2fB", num / 1e9) end
    if num >= 1e6 then return string.format("%.2fM", num / 1e6) end
    if num >= 1e3 then return string.format("%.2fK", num / 1e3) end
    return string.format("%.2f", num)
end

local function miniGraph(prices, width)
    width = width or 15
    local bars = "▁▂▃▄▅▆▇█"

    if not prices or #prices == 0 then
        return string.rep(bars:sub(1,1), width)
    end

    local min = math.huge
    local max = -math.huge
    for _, v in ipairs(prices) do
        if v < min then min = v end
        if v > max then max = v end
    end

    local range = max - min
    if range == 0 then range = 1 end

    local graph = ""
    local startIdx = math.max(1, #prices - width + 1)
    for i = startIdx, #prices do
        local normalized = (prices[i] - min) / range
        local barIdx = math.min(8, math.floor(normalized * 7) + 1)
        graph = graph .. bars:sub(barIdx, barIdx)
    end

    return graph
end

local function getSymbolName(symbol)
    return symbol:gsub("USDT", ""):gsub("BTC", ""):gsub("ETH", "")
end

local function getChangeColor(change)
    local num = tonumber(change) or 0
    return num >= 0 and "🟢" or "🔴"
end

local function checkPriceAlerts(symbol, price)
    if not CONFIG.alerts[symbol] or not price then return end

    local alert = CONFIG.alerts[symbol]
    local alertKey = symbol .. "_"

    if alert.above and price >= alert.above then
        local key = alertKey .. "above"
        if not state.alertTriggered[key] then
            state.alertTriggered[key] = true
            ui:show_toast("🔔 " .. symbol .. " above $" .. fmtPrice(alert.above) .. "!")
        end
    elseif alert.above then
        state.alertTriggered[alertKey .. "above"] = false
    end

    if alert.below and price <= alert.below then
        local key = alertKey .. "below"
        if not state.alertTriggered[key] then
            state.alertTriggered[key] = true
            ui:show_toast("🔔 " .. symbol .. " below $" .. fmtPrice(alert.below) .. "!")
        end
    elseif alert.below then
        state.alertTriggered[alertKey .. "below"] = false
    end
end

-- DISPLAY FUNCTION

local function showPrices()
    if state.error then
        ui:show_text("❌ Connection failed\n\n" .. state.error .. "\n\nTap to retry")
        return
    end

    if not state.tickers or #state.tickers == 0 then
        ui:show_text("💰 No price data\n\nTap to refresh\nLong press for options")
        return
    end

    local o = "💰 Crypto Prices (" .. #state.tickers .. ")\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"

    for _, ticker in ipairs(state.tickers) do
        local symbol = ticker.symbol
        local name = getSymbolName(symbol)
        local namePad = string.rep(" ", 6 - #name)
        local price = fmtPrice(ticker.lastPrice)
        local pricePad = string.rep(" ", 12 - #price)
        local changeColor = getChangeColor(ticker.priceChangePercent)
        local change = fmtPercent(ticker.priceChangePercent)

        o = o .. "\n" .. name .. namePad .. " " .. price .. pricePad .. " " .. changeColor .. " " .. change .. "\n"

        if CONFIG.showGraphs and state.priceHistory[symbol] and #state.priceHistory[symbol] > 1 then
            o = o .. "     " .. miniGraph(state.priceHistory[symbol], 20) .. "\n"
        end

        -- 24h Price Range
        local high = fmtPrice(ticker.highPrice)
        local low = fmtPrice(ticker.lowPrice)
        local current = tonumber(ticker.lastPrice) or 0
        local highNum = tonumber(ticker.highPrice) or current
        local lowNum = tonumber(ticker.lowPrice) or current
        local range = highNum - lowNum
        local position = range > 0 and ((current - lowNum) / range) or 0.5

        -- Visual range indicator
        local rangeBar = ""
        local barWidth = 15
        local pos = math.floor(position * barWidth)
        for i = 1, barWidth do
            rangeBar = rangeBar .. (i == pos and "|" or "=")
        end

        local vol = fmtVolume(ticker.volume)
        local vol24h = fmtVolume(ticker.quoteVolume or ticker.volume)
        o = o .. "     " .. rangeBar .. "\n"
        o = o .. "     H: " .. high .. " L: " .. low .. "\n"
        o = o .. "     Vol: " .. vol .. " (24h: " .. vol24h .. ")\n"

        -- Volume trend
        if ticker.volume and ticker.quoteVolume then
            local volNum = tonumber(ticker.volume)
            local quoteVol = tonumber(ticker.quoteVolume)
            if volNum and quoteVol and quoteVol > 0 then
                local volRatio = volNum / quoteVol
                if volRatio > 1.5 then
                    o = o .. "     📈 High volume activity\n"
                elseif volRatio < 0.5 then
                    o = o .. "     📉 Low volume\n"
                end
            end
        end
    end

    o = o .. "\n🔗 Tap: Refresh │ Long: Options"
    ui:show_text(o)
end

-- BUILD URL FOR BATCH REQUEST

local function urlEncode(str)
    if not str then return "" end
    str = string.gsub(str, "([^%w%-_.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

local function buildBatchUrl()
    local symbolsStr = ""
    for i, symbol in ipairs(CONFIG.symbols) do
        if i > 1 then symbolsStr = symbolsStr .. "," end
        symbolsStr = symbolsStr .. '"' .. symbol .. '"'
    end
    -- URL encode the symbols parameter (brackets and quotes)
    local encoded = urlEncode("[" .. symbolsStr .. "]")
    return "https://api.binance.com/api/v3/ticker/24hr?symbols=" .. encoded
end

-- NETWORK CALLBACKS (AIO Launcher event-driven API)

function on_network_result_tickers(body, code)
    if code ~= 200 or not body or body == "" then
        if code == 429 then
            state.error = "Rate limit exceeded. Please wait."
        elseif code == 418 then
            state.error = "IP banned. Please wait before retrying."
        elseif code == 503 then
            state.error = "Service temporarily unavailable."
        else
            state.error = "HTTP " .. tostring(code)
        end
        showPrices()
        return
    end

    local ok, data = pcall(function() return json:decode(body) end)
    if not ok or not data or type(data) ~= "table" then
        state.error = "Invalid response from Binance"
        showPrices()
        return
    end

    state.error = nil
    state.tickers = data

    -- Update price history and check alerts
    for _, ticker in ipairs(data) do
        local symbol = ticker.symbol
        if symbol then
            if not state.priceHistory[symbol] then
                state.priceHistory[symbol] = {}
            end

            local price = tonumber(ticker.lastPrice)
            if price then
                table.insert(state.priceHistory[symbol], price)
                if #state.priceHistory[symbol] > CONFIG.graphHistory then
                    table.remove(state.priceHistory[symbol], 1)
                end
                checkPriceAlerts(symbol, price)
            end
        end
    end

    showPrices()
end

function on_network_error_tickers(err)
    state.error = err or "Network error"
    showPrices()
end

-- MAIN ENTRY POINTS

function on_resume()
    ui:show_text("⏳ Fetching crypto prices...")
    state.error = nil
    http:get(buildBatchUrl(), "tickers")
end

function on_click()
    on_resume()
end

function on_long_click()
    local alertCount = 0
    for _ in pairs(CONFIG.alerts) do
        alertCount = alertCount + 1
    end

    ui:show_context_menu({
        "🔄 Force Refresh",
        "📈 Graphs: " .. (CONFIG.showGraphs and "On" or "Off"),
        "🔔 Alerts: " .. alertCount .. " active",
        "📋 Edit Watchlist",
        "❌ Close"
    })
end

function on_context_menu_click(idx)
    if idx == 0 then
        on_resume()
    elseif idx == 1 then
        CONFIG.showGraphs = not CONFIG.showGraphs
        ui:show_toast("Graphs: " .. (CONFIG.showGraphs and "On" or "Off"))
        showPrices()
    elseif idx == 2 then
        ui:show_toast("Configure alerts in CONFIG.alerts")
    elseif idx == 3 then
        ui:show_toast("Edit symbols in config")
    end
end

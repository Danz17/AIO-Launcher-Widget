-- name = "Crypto Prices"
-- description = "Cryptocurrency price tracker (Binance)"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    symbols = {"BTCUSDT", "ETHUSDT", "BNBUSDT"},
    refreshInterval = 30,
    showGraphs = true,
    graphHistory = 20,
    rateLimitPerMin = 1200,  -- Binance allows 1200 requests per minute
    cacheTTL = 5,  -- Cache prices for 5 seconds
    alerts = {  -- Price alerts: {symbol = {above = price, below = price}}
        -- Example: ["BTCUSDT"] = {above = 50000, below = 40000}
    }
}

-- Rate limiting state
local rateLimitState = {
    requests = {},
    lastRequestTime = 0
}

-- Price cache
local priceCache = {}
local cacheTime = {}

-- Alert state (track which alerts have been triggered)
local alertTriggered = {}

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

-- BINANCE API FUNCTIONS

local priceHistory = {}

-- Rate limiting helper
local function checkRateLimit()
    local now = os.time()
    local minuteAgo = now - 60
    
    -- Clean old requests
    local validRequests = {}
    for _, reqTime in ipairs(rateLimitState.requests) do
        if reqTime > minuteAgo then
            table.insert(validRequests, reqTime)
        end
    end
    rateLimitState.requests = validRequests
    
    -- Check if we're at limit
    if #rateLimitState.requests >= CONFIG.rateLimitPerMin then
        return false, "Rate limit exceeded (1200 req/min)"
    end
    
    -- Record this request
    table.insert(rateLimitState.requests, now)
    rateLimitState.lastRequestTime = now
    return true, nil
end

-- Check cache
local function getCachedPrice(symbol)
    if priceCache[symbol] and cacheTime[symbol] then
        local age = os.time() - cacheTime[symbol]
        if age < CONFIG.cacheTTL then
            return priceCache[symbol]
        end
    end
    return nil
end

-- Cache price
local function cachePrice(symbol, data)
    priceCache[symbol] = data
    cacheTime[symbol] = os.time()
end

-- Handle Binance API errors
local function handleBinanceError(code, data)
    if code == 429 then
        return "Rate limit exceeded. Please wait."
    elseif code == 418 then
        return "IP banned. Please wait before retrying."
    elseif code == 503 then
        return "Service temporarily unavailable. Please retry."
    elseif code == 400 then
        return "Bad request. Check symbol names."
    end
    return "HTTP " .. tostring(code)
end

-- Get single ticker (with rate limiting and caching)
local function getTicker(symbol, callback)
    -- Check cache first
    local cached = getCachedPrice(symbol)
    if cached then
        callback(cached, nil)
        return
    end
    
    -- Check rate limit
    local ok, err = checkRateLimit()
    if not ok then
        callback(nil, err)
        return
    end
    
    local url = "https://api.binance.com/api/v3/ticker/24hr?symbol=" .. symbol
    
    http:get(url, function(data, code)
        if code == 429 or code == 418 or code == 503 then
            callback(nil, handleBinanceError(code, data))
            return
        end
        
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res then
                -- Cache the result
                cachePrice(symbol, res)
                
                -- Update price history
                if not priceHistory[symbol] then
                    priceHistory[symbol] = {}
                end
                table.insert(priceHistory[symbol], tonumber(res.lastPrice))
                if #priceHistory[symbol] > CONFIG.graphHistory then
                    table.remove(priceHistory[symbol], 1)
                end
                
                -- Check price alerts
                checkPriceAlerts(symbol, tonumber(res.lastPrice))
                
                callback(res, nil)
                return
            end
        end
        callback(nil, handleBinanceError(code, data) or "Failed to fetch " .. symbol)
    end)
end

-- Batch API: Get multiple tickers in one request
local function getAllTickersBatch(symbols, callback)
    -- Check rate limit
    local ok, err = checkRateLimit()
    if not ok then
        callback(nil, err)
        return
    end
    
    -- Build query string with all symbols
    local symbolsStr = ""
    for i, symbol in ipairs(symbols) do
        if i > 1 then
            symbolsStr = symbolsStr .. ","
        end
        symbolsStr = symbolsStr .. symbol
    end
    
    local url = "https://api.binance.com/api/v3/ticker/24hr?symbols=[" .. symbolsStr .. "]"
    
    http:get(url, function(data, code)
        if code == 429 or code == 418 or code == 503 then
            callback(nil, handleBinanceError(code, data))
            return
        end
        
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res and type(res) == "table" then
                -- Cache all results
                for _, ticker in ipairs(res) do
                    if ticker.symbol then
                        cachePrice(ticker.symbol, ticker)
                        
                        -- Update price history
                        if not priceHistory[ticker.symbol] then
                            priceHistory[ticker.symbol] = {}
                        end
                        table.insert(priceHistory[ticker.symbol], tonumber(ticker.lastPrice))
                        if #priceHistory[ticker.symbol] > CONFIG.graphHistory then
                            table.remove(priceHistory[ticker.symbol], 1)
                        end
                        
                        -- Check price alerts
                        checkPriceAlerts(ticker.symbol, tonumber(ticker.lastPrice))
                    end
                end
                
                callback(res, nil)
                return
            end
        end
        callback(nil, handleBinanceError(code, data) or "Failed to fetch prices")
    end)
end

-- Fallback: Get all tickers individually (if batch fails)
local function getAllTickers(symbols, callback)
    -- Try batch API first
    getAllTickersBatch(symbols, function(batchResults, batchErr)
        if batchResults and #batchResults > 0 then
            callback(batchResults, nil)
            return
        end
        
        -- Fallback to individual requests
        local results = {}
        local pending = #symbols
        local hasError = false
        
        for _, symbol in ipairs(symbols) do
            getTicker(symbol, function(data, err)
                pending = pending - 1
                
                if err then
                    hasError = true
                elseif data then
                    table.insert(results, data)
                end
                
                if pending == 0 then
                    if #results > 0 then
                        callback(results, nil)
                    else
                        callback(nil, batchErr or "Failed to fetch prices")
                    end
                end
            end)
        end
    end)
end

-- Price alert checking
local function checkPriceAlerts(symbol, price)
    if not CONFIG.alerts[symbol] or not price then
        return
    end
    
    local alert = CONFIG.alerts[symbol]
    local alertKey = symbol .. "_"
    
    -- Check above threshold
    if alert.above and price >= alert.above then
        local key = alertKey .. "above"
        if not alertTriggered[key] then
            alertTriggered[key] = true
            system:toast("🔔 " .. symbol .. " above $" .. fmtPrice(alert.above) .. "!")
        end
    else
        -- Reset if price drops below
        if alert.above then
            local key = alertKey .. "above"
            if price < alert.above then
                alertTriggered[key] = false
            end
        end
    end
    
    -- Check below threshold
    if alert.below and price <= alert.below then
        local key = alertKey .. "below"
        if not alertTriggered[key] then
            alertTriggered[key] = true
            system:toast("🔔 " .. symbol .. " below $" .. fmtPrice(alert.below) .. "!")
        end
    else
        -- Reset if price rises above
        if alert.below then
            local key = alertKey .. "below"
            if price > alert.below then
                alertTriggered[key] = false
            end
        end
    end
end

-- MAIN FUNCTION

function on_resume()
    ui:show_text("⏳ Fetching crypto prices...")
    
    getAllTickers(CONFIG.symbols, function(tickers, err)
        if err then
            ui:show_text("❌ Connection failed\n\n" .. err .. "\n\nTap to retry")
            return
        end
        
        if not tickers or #tickers == 0 then
            ui:show_text("💰 No price data\n\nTap to refresh\nLong press for options")
            return
        end
        
        showPrices(tickers)
    end)
end

function showPrices(tickers)
    local o = "💰 Crypto Prices (" .. #tickers .. ")\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    for _, ticker in ipairs(tickers) do
        local symbol = ticker.symbol
        local name = getSymbolName(symbol)
        local namePad = string.rep(" ", 6 - #name)
        local price = fmtPrice(ticker.lastPrice)
        local pricePad = string.rep(" ", 12 - #price)
        local changeColor = getChangeColor(ticker.priceChangePercent)
        local change = fmtPercent(ticker.priceChangePercent)
        
        o = o .. "\n" .. name .. namePad .. " " .. price .. pricePad .. " " .. changeColor .. " " .. change .. "\n"
        
        if CONFIG.showGraphs and priceHistory[symbol] and #priceHistory[symbol] > 1 then
            o = o .. "     " .. miniGraph(priceHistory[symbol], 20) .. "\n"
        end
        
        -- 24h Price Range with visual indicators
        local high = fmtPrice(ticker.highPrice)
        local low = fmtPrice(ticker.lowPrice)
        local current = tonumber(ticker.lastPrice) or 0
        local highNum = tonumber(ticker.highPrice) or current
        local lowNum = tonumber(ticker.lowPrice) or current
        local range = highNum - lowNum
        local position = range > 0 and ((current - lowNum) / range) or 0.5
        
        -- Visual range indicator: [====|====]
        local rangeBar = ""
        local barWidth = 15
        local pos = math.floor(position * barWidth)
        for i = 1, barWidth do
            if i == pos then
                rangeBar = rangeBar .. "|"
            else
                rangeBar = rangeBar .. "="
            end
        end
        
        local vol = fmtVolume(ticker.volume)
        local vol24h = fmtVolume(ticker.quoteVolume or ticker.volume)
        o = o .. "     " .. rangeBar .. "\n"
        o = o .. "     H: " .. high .. " L: " .. low .. "\n"
        o = o .. "     Vol: " .. vol .. " (24h: " .. vol24h .. ")\n"
        
        -- Volume trend analysis
        if ticker.volume and ticker.quoteVolume then
            local volRatio = tonumber(ticker.volume) / (tonumber(ticker.quoteVolume) or 1)
            if volRatio > 1.5 then
                o = o .. "     📈 High volume activity\n"
            elseif volRatio < 0.5 then
                o = o .. "     📉 Low volume\n"
            end
        end
    end
    
    o = o .. "\n🔗 Tap: Refresh │ Long: Options"
    
    ui:show_text(o)
end

function on_click()
    on_resume()
end

function on_long_click()
    -- Count active alerts
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
    }, function(index)
        if index == 0 then
            on_resume()
        elseif index == 1 then
            CONFIG.showGraphs = not CONFIG.showGraphs
            system:toast("Graphs: " .. (CONFIG.showGraphs and "On" or "Off"))
            on_resume()
        elseif index == 2 then
            system:toast("Configure alerts in CONFIG.alerts")
        elseif index == 3 then
            system:toast("Edit symbols in config")
        end
    end)
end


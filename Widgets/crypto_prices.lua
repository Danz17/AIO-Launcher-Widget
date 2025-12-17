-- name = "Crypto Prices"
-- description = "Cryptocurrency price tracker (Binance)"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    symbols = {"BTCUSDT", "ETHUSDT", "BNBUSDT"},
    refreshInterval = 30,
    showGraphs = true,
    graphHistory = 20
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

-- BINANCE API FUNCTIONS

local priceHistory = {}

local function getTicker(symbol, callback)
    local url = "https://api.binance.com/api/v3/ticker/24hr?symbol=" .. symbol
    
    http:get(url, function(data, code)
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res then
                -- Update price history
                if not priceHistory[symbol] then
                    priceHistory[symbol] = {}
                end
                table.insert(priceHistory[symbol], tonumber(res.lastPrice))
                if #priceHistory[symbol] > CONFIG.graphHistory then
                    table.remove(priceHistory[symbol], 1)
                end
                
                callback(res, nil)
                return
            end
        end
        callback(nil, "Failed to fetch " .. symbol)
    end)
end

local function getAllTickers(symbols, callback)
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
                    callback(nil, "Failed to fetch prices")
                end
            end
        end)
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
        
        local high = fmtPrice(ticker.highPrice)
        local low = fmtPrice(ticker.lowPrice)
        local vol = fmtVolume(ticker.volume)
        o = o .. "     Vol: " .. vol .. " │ H: " .. high .. " L: " .. low .. "\n"
    end
    
    o = o .. "\n🔗 Tap: Refresh │ Long: Options"
    
    ui:show_text(o)
end

function on_click()
    on_resume()
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Force Refresh",
        "📈 Graphs: " .. (CONFIG.showGraphs and "On" or "Off"),
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
            system:toast("Edit symbols in config")
        end
    end)
end


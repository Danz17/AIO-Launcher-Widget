// ============================================================================
// Cryptocurrency Prices Widget for AIO Launcher (Binance)
// ============================================================================

// Configuration - can be overridden via storage
const DEFAULT_CONFIG = {
    symbols: ["BTCUSDT", "ETHUSDT", "BNBUSDT"],
    refreshInterval: 30,
    showGraphs: true,
    graphHistory: 20,
    priceAlerts: {},
    retryAttempts: 3,
    retryDelay: 1000
};

// ============================================================================
// Utility Functions
// ============================================================================

function getConfig() {
    const stored = aio.storage.get("crypto_config") || {};
    return { ...DEFAULT_CONFIG, ...stored };
}

function fmtPrice(price) {
    if (!price) return "0.00";
    const num = parseFloat(price);
    if (num >= 1000) return num.toFixed(2);
    if (num >= 1) return num.toFixed(4);
    if (num >= 0.01) return num.toFixed(6);
    return num.toFixed(8);
}

function fmtPercent(percent) {
    if (!percent) return "0.00%";
    const num = parseFloat(percent);
    const sign = num >= 0 ? "+" : "";
    return `${sign}${num.toFixed(2)}%`;
}

function fmtVolume(volume) {
    if (!volume) return "0";
    const num = parseFloat(volume);
    if (num >= 1e9) return (num / 1e9).toFixed(2) + "B";
    if (num >= 1e6) return (num / 1e6).toFixed(2) + "M";
    if (num >= 1e3) return (num / 1e3).toFixed(2) + "K";
    return num.toFixed(2);
}

function miniGraph(prices, width = 15) {
    const bars = "▁▂▃▄▅▆▇█";
    if (!prices || prices.length === 0) return bars[0].repeat(width);
    const min = Math.min(...prices);
    const max = Math.max(...prices);
    const range = max - min || 1;
    return prices.slice(-width).map(v => {
        const normalized = (v - min) / range;
        return bars[Math.min(7, Math.floor(normalized * 7))] || bars[0];
    }).join("");
}

function getSymbolName(symbol) {
    return symbol.replace("USDT", "").replace("BTC", "").replace("ETH", "");
}

function getChangeColor(change) {
    const num = parseFloat(change) || 0;
    return num >= 0 ? "🟢" : "🔴";
}

// ============================================================================
// API Functions with Retry Logic
// ============================================================================

async function getTicker(symbol, config) {
    const maxRetries = config.retryAttempts;
    const url = `https://api.binance.com/api/v3/ticker/24hr?symbol=${symbol}`;
    
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            const response = await fetch(url);
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            const data = await response.json();
            return data;
        } catch (e) {
            if (attempt === maxRetries) {
                console.error(`API GET failed for ${symbol}:`, e);
                return null;
            }
            await new Promise(resolve => setTimeout(resolve, config.retryDelay));
        }
    }
    return null;
}

async function getKlines(symbol, interval = "1h", limit = 24, config) {
    const maxRetries = config.retryAttempts;
    const url = `https://api.binance.com/api/v3/klines?symbol=${symbol}&interval=${interval}&limit=${limit}`;
    
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            const response = await fetch(url);
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            const data = await response.json();
            return data;
        } catch (e) {
            if (attempt === maxRetries) {
                console.error(`Klines API failed for ${symbol}:`, e);
                return null;
            }
            await new Promise(resolve => setTimeout(resolve, config.retryDelay));
        }
    }
    return null;
}

// ============================================================================
// Main Widget Function
// ============================================================================

async function main() {
    const config = getConfig();
    const store = aio.storage.get("crypto") || {
        lastUpdate: 0,
        prices: {},
        history: {},
        mode: "full"
    };
    
    const now = Date.now();
    const mode = store.mode || "full";
    const timeSinceUpdate = (now - store.lastUpdate) / 1000;
    
    // Fetch prices if needed
    let prices = store.prices || {};
    let history = store.history || {};
    
    if (timeSinceUpdate >= config.refreshInterval || Object.keys(prices).length === 0) {
        const symbols = config.symbols || DEFAULT_CONFIG.symbols;
        const pricePromises = symbols.map(symbol => getTicker(symbol, config));
        const tickerResults = await Promise.all(pricePromises);
        
        // Process ticker results
        tickerResults.forEach((ticker, index) => {
            if (ticker && symbols[index]) {
                const symbol = symbols[index];
                prices[symbol] = {
                    symbol: symbol,
                    price: ticker.lastPrice,
                    change24h: ticker.priceChangePercent,
                    volume: ticker.volume,
                    high24h: ticker.highPrice,
                    low24h: ticker.lowPrice
                };
                
                // Update history
                if (!history[symbol]) history[symbol] = [];
                history[symbol].push(parseFloat(ticker.lastPrice));
                if (history[symbol].length > config.graphHistory) {
                    history[symbol].shift();
                }
            }
        });
        
        // Fetch klines for graphs if enabled
        if (config.showGraphs) {
            const klinePromises = symbols.map(symbol => getKlines(symbol, "1h", config.graphHistory, config));
            const klineResults = await Promise.all(klinePromises);
            
            klineResults.forEach((klines, index) => {
                if (klines && Array.isArray(klines) && symbols[index]) {
                    const symbol = symbols[index];
                    // Extract closing prices (index 4)
                    const closePrices = klines.map(k => parseFloat(k[4]));
                    history[symbol] = closePrices;
                }
            });
        }
        
        store.lastUpdate = now;
        store.prices = prices;
        store.history = history;
        aio.storage.set("crypto", store);
        
        // Check price alerts
        checkPriceAlerts(prices, config);
    }
    
    // Generate output
    let o = "";
    
    if (mode === "compact") {
        const firstSymbol = config.symbols[0];
        const firstPrice = prices[firstSymbol];
        if (firstPrice) {
            const changeColor = getChangeColor(firstPrice.change24h);
            o += `${getSymbolName(firstSymbol)} ${fmtPrice(firstPrice.price)}\n`;
            o += `${changeColor} ${fmtPercent(firstPrice.change24h)}\n`;
            if (config.showGraphs && history[firstSymbol]) {
                o += `${miniGraph(history[firstSymbol], 15)}\n`;
            }
            o += `\n${config.symbols.length} coins\n`;
            o += `Tap: Refresh │ Long: Options`;
        } else {
            o += "📊 Loading prices...\n\n";
            o += "Tap: Refresh │ Long: Options";
        }
        return o;
    }
    
    // Full mode
    o += `💰 Crypto Prices (${config.symbols.length})\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    
    if (Object.keys(prices).length === 0) {
        o += "\nNo price data\n";
        o += "Tap to refresh\n";
        o += "Long press for options";
        return o;
    }
    
    for (const symbol of config.symbols) {
        const price = prices[symbol];
        if (!price) continue;
        
        const name = getSymbolName(symbol).padEnd(6);
        const priceStr = fmtPrice(price.price).padStart(12);
        const changeColor = getChangeColor(price.change24h);
        const changeStr = fmtPercent(price.change24h);
        
        o += `${name} ${priceStr} ${changeColor} ${changeStr}\n`;
        
        if (config.showGraphs && history[symbol] && history[symbol].length > 0) {
            o += `     ${miniGraph(history[symbol], 20)}\n`;
        }
        
        o += `     Vol: ${fmtVolume(price.volume)} │ H: ${fmtPrice(price.high24h)} L: ${fmtPrice(price.low24h)}\n`;
    }
    
    o += `\n🔗 Tap: Refresh │ Long: Options`;
    
    return o;
}

function checkPriceAlerts(prices, config) {
    const alerts = config.priceAlerts || {};
    const store = aio.storage.get("crypto_alerts") || {};
    
    for (const symbol in alerts) {
        const price = prices[symbol];
        if (!price) continue;
        
        const currentPrice = parseFloat(price.price);
        const alertPrice = parseFloat(alerts[symbol]);
        const alertKey = `${symbol}_${alertPrice}`;
        
        if (store[alertKey]) continue; // Already alerted
        
        if (currentPrice >= alertPrice) {
            aio.notify(`💰 ${getSymbolName(symbol)} Alert`, `Price reached ${fmtPrice(alertPrice)}`);
            store[alertKey] = true;
        }
    }
    
    aio.storage.set("crypto_alerts", store);
}

// ============================================================================
// Event Handlers
// ============================================================================

aio.onTap = function() {
    const store = aio.storage.get("crypto") || {};
    store.lastUpdate = 0; // Force refresh
    aio.storage.set("crypto", store);
    aio.refresh();
};

aio.onLongTap = function() {
    const config = getConfig();
    const store = aio.storage.get("crypto") || {};
    
    aio.menu([
        "📊 Toggle Compact/Full Mode",
        "🔄 Force Refresh",
        "📈 Toggle Graphs",
        "📋 Edit Watchlist",
        "🔔 Price Alerts",
        "⚙️ Settings",
        "❌ Cancel"
    ], async (index) => {
        switch(index) {
            case 0:
                store.mode = store.mode === "compact" ? "full" : "compact";
                aio.storage.set("crypto", store);
                aio.refresh();
                break;
            case 1:
                store.lastUpdate = 0;
                aio.storage.set("crypto", store);
                aio.toast("Refreshing...");
                aio.refresh();
                break;
            case 2:
                const newConfig = getConfig();
                newConfig.showGraphs = !newConfig.showGraphs;
                aio.storage.set("crypto_config", newConfig);
                aio.toast(`Graphs: ${newConfig.showGraphs ? "On" : "Off"}`);
                aio.refresh();
                break;
            case 3:
                aio.toast("Edit watchlist in config (symbols array)");
                break;
            case 4:
                aio.toast("Price alerts: Edit in config (priceAlerts object)");
                break;
            case 5:
                showSettingsMenu(config);
                break;
        }
    });
};

function showSettingsMenu(config) {
    aio.menu([
        `⏱ Refresh Interval: ${config.refreshInterval}s`,
        `📊 Graph History: ${config.graphHistory}`,
        `📋 Watchlist: ${config.symbols.length} coins`,
        "❌ Cancel"
    ], (index) => {
        aio.toast("Edit settings in config");
    });
}

// ============================================================================
// Initialize
// ============================================================================

main();


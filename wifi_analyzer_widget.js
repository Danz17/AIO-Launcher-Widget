// ============================================================================
// WiFi Analyzer Widget for AIO Launcher
// ============================================================================

// Configuration - can be overridden via storage
const DEFAULT_CONFIG = {
    scanInterval: 30,
    maxNetworksShow: 10,
    showHidden: false,
    sortBy: "signal", // signal, name, security
    retryAttempts: 2,
    retryDelay: 500
};

// ============================================================================
// Utility Functions
// ============================================================================

function getConfig() {
    const stored = aio.storage.get("wifi_config") || {};
    return { ...DEFAULT_CONFIG, ...stored };
}

function signalBar(dbm) {
    const s = parseInt(dbm) || -100;
    if (s >= -50) return "████";
    if (s >= -60) return "███░";
    if (s >= -70) return "██░░";
    if (s >= -80) return "█░░░";
    return "░░░░";
}

function signalIcon(dbm) {
    const s = parseInt(dbm) || -100;
    if (s >= -65) return "📶";
    if (s >= -75) return "📶";
    if (s >= -85) return "📉";
    return "⚠️";
}

function getSecurityType(capabilities) {
    if (!capabilities) return "Open";
    const caps = capabilities.toUpperCase();
    if (caps.includes("WPA3")) return "WPA3";
    if (caps.includes("WPA2")) return "WPA2";
    if (caps.includes("WPA")) return "WPA";
    if (caps.includes("WEP")) return "WEP";
    return "Open";
}

function getFrequency(centerFreq0, centerFreq1) {
    if (centerFreq0 >= 5000) return "5GHz";
    if (centerFreq0 >= 2400) return "2.4GHz";
    if (centerFreq1 >= 5000) return "5GHz";
    return "2.4GHz";
}

function getChannel(freq) {
    if (!freq) return "?";
    if (freq >= 5000) {
        return Math.floor((freq - 5000) / 5);
    }
    if (freq >= 2400) {
        return Math.floor((freq - 2400) / 5);
    }
    return "?";
}

function sortNetworks(networks, sortBy) {
    const sorted = [...networks];
    switch(sortBy) {
        case "signal":
            return sorted.sort((a, b) => (b.rssi || -100) - (a.rssi || -100));
        case "name":
            return sorted.sort((a, b) => (a.ssid || "").localeCompare(b.ssid || ""));
        case "security":
            return sorted.sort((a, b) => {
                const secA = getSecurityType(a.capabilities);
                const secB = getSecurityType(b.capabilities);
                return secA.localeCompare(secB);
            });
        default:
            return sorted;
    }
}

// ============================================================================
// WiFi Scanning Functions
// ============================================================================

async function scanWiFi() {
    try {
        // Attempt to use AIO launcher WiFi API if available
        if (typeof aio.wifi !== "undefined" && aio.wifi.scan) {
            const results = await aio.wifi.scan();
            return results || [];
        }
        
        // Fallback: Try Android WiFi Manager via bridge
        if (typeof Android !== "undefined" && Android.getWifiScanResults) {
            const results = Android.getWifiScanResults();
            return JSON.parse(results || "[]");
        }
        
        // If no API available, return mock data structure for testing
        return [];
    } catch (e) {
        console.error("WiFi scan error:", e);
        return null;
    }
}

// ============================================================================
// Main Widget Function
// ============================================================================

async function main() {
    const config = getConfig();
    const store = aio.storage.get("wifi") || {
        lastScan: 0,
        networks: [],
        favorites: [],
        mode: "full"
    };
    
    const now = Date.now();
    const mode = store.mode || "full";
    const timeSinceScan = (now - store.lastScan) / 1000;
    
    // Scan if needed
    let networks = store.networks || [];
    if (timeSinceScan >= config.scanInterval || networks.length === 0) {
        const scanResults = await scanWiFi();
        if (scanResults !== null) {
            networks = Array.isArray(scanResults) ? scanResults : [];
            store.lastScan = now;
            store.networks = networks;
            aio.storage.set("wifi", store);
        }
    }
    
    // Filter hidden networks if needed
    if (!config.showHidden) {
        networks = networks.filter(n => n.ssid && n.ssid.length > 0);
    }
    
    // Process networks
    const processedNetworks = networks.map(net => ({
        ssid: net.ssid || net.SSID || "[Hidden]",
        bssid: net.bssid || net.BSSID || "",
        rssi: net.rssi || net.level || -100,
        frequency: net.frequency || net.freq || 0,
        capabilities: net.capabilities || net.Capabilities || "",
        channel: getChannel(net.frequency || net.freq || 0),
        band: getFrequency(net.frequency || net.freq || 0),
        security: getSecurityType(net.capabilities || net.Capabilities || ""),
        isFavorite: store.favorites.includes(net.bssid || net.BSSID || "")
    }));
    
    // Sort networks
    const sortedNetworks = sortNetworks(processedNetworks, config.sortBy);
    
    // Generate output
    let o = "";
    
    if (mode === "compact") {
        const topNetwork = sortedNetworks[0];
        if (topNetwork) {
            o += `📶 ${topNetwork.ssid.slice(0, 15)}\n`;
            o += `${signalBar(topNetwork.rssi)} ${topNetwork.rssi}dBm\n`;
            o += `${topNetwork.security} │ ${topNetwork.band}\n`;
            o += `\n${sortedNetworks.length} networks\n`;
            o += `Tap: Refresh │ Long: Options`;
        } else {
            o += "📶 No networks found\n\n";
            o += "Tap: Scan │ Long: Options";
        }
        return o;
    }
    
    // Full mode
    o += `📶 WiFi Networks (${sortedNetworks.length})\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    
    if (sortedNetworks.length === 0) {
        o += "\nNo networks found\n";
        o += "Tap to scan for networks\n";
        o += "Long press for options";
        return o;
    }
    
    const displayNetworks = sortedNetworks.slice(0, config.maxNetworksShow);
    
    for (const net of displayNetworks) {
        const fav = net.isFavorite ? "⭐" : " ";
        const ssid = net.ssid.slice(0, 18).padEnd(18);
        const sigBar = signalBar(net.rssi);
        const sec = net.security.padEnd(5);
        o += `${fav} ${ssid} ${sigBar} ${net.rssi}dBm\n`;
        o += `   ${sec} │ Ch${net.channel} │ ${net.band}\n`;
    }
    
    if (sortedNetworks.length > config.maxNetworksShow) {
        o += `\n  +${sortedNetworks.length - config.maxNetworksShow} more\n`;
    }
    
    o += `\n🔗 Tap: Refresh │ Long: Options`;
    
    return o;
}

// ============================================================================
// Event Handlers
// ============================================================================

aio.onTap = function() {
    const store = aio.storage.get("wifi") || {};
    store.lastScan = 0; // Force refresh
    aio.storage.set("wifi", store);
    aio.refresh();
};

aio.onLongTap = function() {
    const config = getConfig();
    const store = aio.storage.get("wifi") || {};
    
    aio.menu([
        "📊 Toggle Compact/Full Mode",
        "🔄 Force Scan Now",
        `👁️ Show Hidden: ${config.showHidden ? "Yes" : "No"}`,
        `🔀 Sort By: ${config.sortBy}`,
        `📋 Max Networks: ${config.maxNetworksShow}`,
        "⭐ Manage Favorites",
        "🗑️ Clear Cache",
        "❌ Cancel"
    ], async (index) => {
        switch(index) {
            case 0:
                store.mode = store.mode === "compact" ? "full" : "compact";
                aio.storage.set("wifi", store);
                aio.refresh();
                break;
            case 1:
                store.lastScan = 0;
                aio.storage.set("wifi", store);
                aio.toast("Scanning...");
                aio.refresh();
                break;
            case 2:
                const newConfig = getConfig();
                newConfig.showHidden = !newConfig.showHidden;
                aio.storage.set("wifi_config", newConfig);
                aio.toast(`Show hidden: ${newConfig.showHidden ? "Yes" : "No"}`);
                aio.refresh();
                break;
            case 3:
                const sortOptions = ["signal", "name", "security"];
                const currentIndex = sortOptions.indexOf(config.sortBy);
                const nextSort = sortOptions[(currentIndex + 1) % sortOptions.length];
                const updatedConfig = getConfig();
                updatedConfig.sortBy = nextSort;
                aio.storage.set("wifi_config", updatedConfig);
                aio.toast(`Sort by: ${nextSort}`);
                aio.refresh();
                break;
            case 4:
                // Max networks setting would need input dialog
                aio.toast("Edit max networks in config");
                break;
            case 5:
                showFavoritesMenu(store);
                break;
            case 6:
                aio.confirm("Clear scan cache?", () => {
                    store.networks = [];
                    store.lastScan = 0;
                    aio.storage.set("wifi", store);
                    aio.toast("Cache cleared");
                    aio.refresh();
                });
                break;
        }
    });
};

function showFavoritesMenu(store) {
    const favorites = store.favorites || [];
    if (favorites.length === 0) {
        aio.toast("No favorites yet");
        return;
    }
    
    // Get favorite network names
    const networks = store.networks || [];
    const favoriteNetworks = favorites.map(bssid => {
        const net = networks.find(n => (n.bssid || n.BSSID) === bssid);
        return { bssid, ssid: net?.ssid || net?.SSID || "Unknown" };
    });
    
    const menuItems = favoriteNetworks.map(n => `⭐ ${n.ssid.slice(0, 20)}`);
    menuItems.push("❌ Cancel");
    
    aio.menu(menuItems, (index) => {
        if (index < favoriteNetworks.length) {
            aio.confirm(`Remove ${favoriteNetworks[index].ssid} from favorites?`, () => {
                store.favorites = store.favorites.filter(b => b !== favoriteNetworks[index].bssid);
                aio.storage.set("wifi", store);
                aio.toast("Removed from favorites");
                aio.refresh();
            });
        }
    });
}

// ============================================================================
// Initialize
// ============================================================================

main();


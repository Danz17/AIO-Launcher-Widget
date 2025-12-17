// ============================================================================
// Enpass Password Manager Widget for AIO Launcher
// ============================================================================

// Configuration - can be overridden via storage
const DEFAULT_CONFIG = {
    serverUrl: "", // Leave empty for local vault
    apiKey: "",
    vaultPath: "", // Local vault path (if applicable)
    retryAttempts: 2,
    retryDelay: 500
};

// ============================================================================
// Utility Functions
// ============================================================================

function getConfig() {
    const stored = aio.storage.get("enpass_config") || {};
    return { ...DEFAULT_CONFIG, ...stored };
}

function fmtDate(timestamp) {
    if (!timestamp) return "Never";
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now - date;
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);
    
    if (diffMins < 1) return "Just now";
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
}

function progressBar(percent, width = 10) {
    const filled = Math.round((percent / 100) * width);
    return "█".repeat(filled) + "░".repeat(width - filled);
}

// ============================================================================
// Enpass API Functions
// ============================================================================

async function enpassRequest(endpoint, method = "GET", body = null, config) {
    if (!config.serverUrl) {
        // Local vault - check file system or use local APIs
        return checkLocalVault(config);
    }
    
    const url = `${config.serverUrl}${endpoint}`;
    const headers = {
        "Content-Type": "application/json"
    };
    
    if (config.apiKey) {
        headers["Authorization"] = `Bearer ${config.apiKey}`;
    }
    
    try {
        const options = {
            method: method,
            headers: headers
        };
        
        if (body && method !== "GET") {
            options.body = JSON.stringify(body);
        }
        
        const response = await fetch(url, options);
        
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        
        const data = await response.json();
        return data;
    } catch (e) {
        console.error(`Enpass API error (${endpoint}):`, e);
        return null;
    }
}

async function checkLocalVault(config) {
    // Try to check local vault status
    // This would require platform-specific APIs
    try {
        if (typeof aio.enpass !== "undefined") {
            return await aio.enpass.getStatus();
        }
        
        // Fallback: Return mock structure for local vault
        return {
            locked: true,
            itemCount: 0,
            lastSync: null,
            syncStatus: "unknown"
        };
    } catch (e) {
        return null;
    }
}

async function getVaultStatus(config) {
    if (config.serverUrl) {
        return await enpassRequest("/api/v1/status", "GET", null, config);
    } else {
        return await checkLocalVault(config);
    }
}

async function getVaultStats(config) {
    if (config.serverUrl) {
        return await enpassRequest("/api/v1/stats", "GET", null, config);
    } else {
        return null;
    }
}

// ============================================================================
// Main Widget Function
// ============================================================================

async function main() {
    const config = getConfig();
    const store = aio.storage.get("enpass") || {
        lastCheck: 0,
        status: null,
        stats: null,
        mode: "full"
    };
    
    const now = Date.now();
    const mode = store.mode || "full";
    const timeSinceCheck = (now - store.lastCheck) / 1000;
    
    // Fetch status if needed (check every 60 seconds)
    let status = store.status;
    let stats = store.stats;
    
    if (timeSinceCheck >= 60 || !status) {
        const [statusData, statsData] = await Promise.all([
            getVaultStatus(config),
            getVaultStats(config)
        ]);
        
        if (statusData) {
            status = statusData;
            store.status = status;
            store.lastCheck = now;
        }
        
        if (statsData) {
            stats = statsData;
            store.stats = stats;
        }
        
        aio.storage.set("enpass", store);
    }
    
    if (!status) {
        return "❌ Cannot access vault\n\nCheck configuration\nLong press for options";
    }
    
    // Process status
    const isLocked = status.locked !== false;
    const itemCount = status.itemCount || stats?.totalItems || 0;
    const lastSync = status.lastSync || stats?.lastSyncTime || null;
    const syncStatus = status.syncStatus || "unknown";
    const syncProvider = status.syncProvider || stats?.syncProvider || "Local";
    const weakPasswords = stats?.weakPasswords || 0;
    const duplicatePasswords = stats?.duplicatePasswords || 0;
    
    // Calculate security score
    let securityScore = 100;
    if (weakPasswords > 0) securityScore -= Math.min(30, weakPasswords * 2);
    if (duplicatePasswords > 0) securityScore -= Math.min(20, duplicatePasswords * 2);
    if (syncStatus === "error") securityScore -= 10;
    securityScore = Math.max(0, securityScore);
    
    // Generate output
    let o = "";
    
    if (mode === "compact") {
        const lockIcon = isLocked ? "🔒" : "🔓";
        o += `${lockIcon} Enpass\n`;
        o += `📦 ${itemCount} Items\n`;
        o += `🔄 ${syncStatus === "synced" ? "✓" : syncStatus === "syncing" ? "⟳" : "✗"}\n`;
        o += `\nTap: Open │ Long: Options`;
        return o;
    }
    
    // Full mode
    const lockIcon = isLocked ? "🔒" : "🔓";
    const lockStatus = isLocked ? "Locked" : "Unlocked";
    o += `${lockIcon} Enpass Vault - ${lockStatus}\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    
    o += `\n📦 VAULT INFO\n`;
    o += `Items: ${itemCount}\n`;
    o += `Status: ${lockStatus}\n`;
    
    o += `\n🔄 SYNC STATUS\n`;
    const syncIcon = syncStatus === "synced" ? "✅" : syncStatus === "syncing" ? "⟳" : "❌";
    o += `${syncIcon} ${syncStatus.charAt(0).toUpperCase() + syncStatus.slice(1)}\n`;
    o += `Provider: ${syncProvider}\n`;
    o += `Last Sync: ${fmtDate(lastSync)}\n`;
    
    o += `\n🔐 SECURITY\n`;
    o += `Score ${progressBar(securityScore, 10)} ${securityScore}%\n`;
    if (weakPasswords > 0) {
        o += `⚠️ Weak: ${weakPasswords}\n`;
    }
    if (duplicatePasswords > 0) {
        o += `⚠️ Duplicate: ${duplicatePasswords}\n`;
    }
    if (weakPasswords === 0 && duplicatePasswords === 0) {
        o += `✅ All passwords secure\n`;
    }
    
    o += `\n🔗 Tap: Open Enpass │ Long: Options`;
    
    return o;
}

// ============================================================================
// Event Handlers
// ============================================================================

aio.onTap = function() {
    // Try to open Enpass app
    try {
        if (typeof aio.openApp !== "undefined") {
            aio.openApp("com.sinex.enpass");
        } else {
            aio.toast("Open Enpass manually");
        }
    } catch (e) {
        aio.toast("Open Enpass manually");
    }
};

aio.onLongTap = function() {
    const config = getConfig();
    const store = aio.storage.get("enpass") || {};
    
    aio.menu([
        "📊 Toggle Compact/Full Mode",
        "🔄 Force Refresh",
        "🔐 Configure Vault",
        "⚙️ Settings",
        "❌ Cancel"
    ], async (index) => {
        switch(index) {
            case 0:
                store.mode = store.mode === "compact" ? "full" : "compact";
                aio.storage.set("enpass", store);
                aio.refresh();
                break;
            case 1:
                store.lastCheck = 0;
                aio.storage.set("enpass", store);
                aio.toast("Refreshing...");
                aio.refresh();
                break;
            case 2:
                showVaultConfigMenu(config);
                break;
            case 3:
                showSettingsMenu(config);
                break;
        }
    });
};

function showVaultConfigMenu(config) {
    aio.menu([
        `🌐 Server: ${config.serverUrl || "Local"}`,
        `🔑 API Key: ${config.apiKey ? "Set" : "Not set"}`,
        `📁 Vault Path: ${config.vaultPath || "Default"}`,
        "❌ Cancel"
    ], (index) => {
        aio.toast("Edit vault config in settings");
    });
}

function showSettingsMenu(config) {
    aio.menu([
        `🌐 Server URL: ${config.serverUrl || "Not set"}`,
        `🔑 API Key: ${config.apiKey ? "Set" : "Not set"}`,
        `📁 Vault Path: ${config.vaultPath || "Default"}`,
        "❌ Cancel"
    ], (index) => {
        aio.toast("Edit settings in config");
    });
}

// ============================================================================
// Initialize
// ============================================================================

main();


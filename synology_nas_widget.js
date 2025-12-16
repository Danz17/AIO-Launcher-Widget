// ============================================================================
// Synology NAS Monitor Widget for AIO Launcher
// ============================================================================

// Configuration - can be overridden via storage
const DEFAULT_CONFIG = {
    ip: "192.168.1.100",
    port: 5000,
    username: "admin",
    password: "admin",
    useHTTPS: false,
    retryAttempts: 3,
    retryDelay: 1000
};

// ============================================================================
// Utility Functions
// ============================================================================

function getConfig() {
    const stored = aio.storage.get("syno_config") || {};
    return { ...DEFAULT_CONFIG, ...stored };
}

function getBaseURL(config) {
    const protocol = config.useHTTPS ? "https" : "http";
    return `${protocol}://${config.ip}:${config.port}`;
}

function fmtBytes(bytes) {
    if (!bytes || bytes < 0) return "0B";
    if (bytes >= 1e12) return (bytes/1e12).toFixed(2) + "TB";
    if (bytes >= 1e9) return (bytes/1e9).toFixed(2) + "GB";
    if (bytes >= 1e6) return (bytes/1e6).toFixed(1) + "MB";
    if (bytes >= 1e3) return (bytes/1e3).toFixed(0) + "KB";
    return bytes + "B";
}

function progressBar(percent, width = 10) {
    const filled = Math.round((percent / 100) * width);
    return "█".repeat(filled) + "░".repeat(width - filled);
}

function fmtUptime(seconds) {
    if (!seconds) return "0s";
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (d > 0) return `${d}d ${h}h`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
}

// ============================================================================
// Synology API Functions
// ============================================================================

async function synoLogin(config) {
    const baseURL = getBaseURL(config);
    const session = aio.storage.get("syno_session") || {};
    
    // Check if session is still valid (expires after 20 minutes)
    if (session.sid && session.expires && Date.now() < session.expires) {
        return session.sid;
    }
    
    try {
        const url = `${baseURL}/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=${encodeURIComponent(config.username)}&passwd=${encodeURIComponent(config.password)}&session=FileStation&format=sid`;
        const response = await fetch(url);
        const data = await response.json();
        
        if (data.success && data.data && data.data.sid) {
            const sid = data.data.sid;
            aio.storage.set("syno_session", {
                sid: sid,
                expires: Date.now() + (20 * 60 * 1000) // 20 minutes
            });
            return sid;
        }
        return null;
    } catch (e) {
        console.error("Synology login error:", e);
        return null;
    }
}

async function synoRequest(api, method, params, config) {
    const sid = await synoLogin(config);
    if (!sid) return null;
    
    const baseURL = getBaseURL(config);
    const queryParams = new URLSearchParams({
        api: api,
        version: "1",
        method: method,
        _sid: sid,
        ...params
    });
    
    try {
        const url = `${baseURL}/webapi/${api.toLowerCase()}.cgi?${queryParams.toString()}`;
        const response = await fetch(url);
        const data = await response.json();
        return data.success ? data.data : null;
    } catch (e) {
        console.error(`Synology API error (${api}):`, e);
        return null;
    }
}

async function getSystemInfo(config) {
    return await synoRequest("SYNO.Core.System", "info", {}, config);
}

async function getSystemUtilization(config) {
    return await synoRequest("SYNO.Core.System.Utilization", "get", {}, config);
}

async function getStorageInfo(config) {
    return await synoRequest("SYNO.Storage.CGI.Storage", "load_info", {}, config);
}

async function getNetworkInfo(config) {
    return await synoRequest("SYNO.Core.Network", "list", {}, config);
}

// ============================================================================
// Main Widget Function
// ============================================================================

async function main() {
    const config = getConfig();
    const store = aio.storage.get("syno") || {
        mode: "full"
    };
    
    const mode = store.mode || "full";
    
    // Fetch data in parallel
    const [systemInfo, utilization, storageInfo, networkInfo] = await Promise.all([
        getSystemInfo(config),
        getSystemUtilization(config),
        getStorageInfo(config),
        getNetworkInfo(config)
    ]);
    
    if (!systemInfo) {
        return "❌ Connection failed\n\nCheck IP/credentials\nLong press for options";
    }
    
    // Process system info
    const model = systemInfo.model || "Unknown";
    const version = systemInfo.version_string || "";
    const uptime = systemInfo.uptime || 0;
    
    // Process utilization
    const cpu = utilization?.cpu?.user_load || 0;
    const memTotal = utilization?.memory?.total_kb || 0;
    const memUsed = utilization?.memory?.used_kb || 0;
    const memPercent = memTotal > 0 ? Math.round((memUsed / memTotal) * 100) : 0;
    const networkRx = utilization?.network?.rx || 0;
    const networkTx = utilization?.network?.tx || 0;
    
    // Process storage
    const volumes = storageInfo?.volumes || [];
    const pools = storageInfo?.pools || [];
    let totalSpace = 0;
    let usedSpace = 0;
    
    volumes.forEach(vol => {
        totalSpace += parseInt(vol.size?.total_byte || 0);
        usedSpace += parseInt(vol.size?.used_byte || 0);
    });
    
    const storagePercent = totalSpace > 0 ? Math.round((usedSpace / totalSpace) * 100) : 0;
    const freeSpace = totalSpace - usedSpace;
    
    // Generate output
    let o = "";
    
    if (mode === "compact") {
        o += `🖥 ${model.slice(0, 12)}\n`;
        o += `CPU ${progressBar(cpu, 5)} ${cpu}%\n`;
        o += `RAM ${progressBar(memPercent, 5)} ${memPercent}%\n`;
        o += `💾 ${progressBar(storagePercent, 5)} ${storagePercent}%\n`;
        o += `\nTap: DSM │ Long: Options`;
        return o;
    }
    
    // Full mode
    o += `🖥 ${model} ${version}\n`;
    o += `⏱ Uptime: ${fmtUptime(uptime)}\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    
    o += `\n💻 SYSTEM\n`;
    o += `CPU ${progressBar(cpu, 10)} ${cpu}%\n`;
    o += `RAM ${progressBar(memPercent, 10)} ${memPercent}% (${fmtBytes(memUsed * 1024)}/${fmtBytes(memTotal * 1024)})\n`;
    
    o += `\n💾 STORAGE\n`;
    o += `Used ${progressBar(storagePercent, 10)} ${storagePercent}%\n`;
    o += `Free: ${fmtBytes(freeSpace)} / Total: ${fmtBytes(totalSpace)}\n`;
    
    if (volumes.length > 0) {
        o += `\nVolumes:\n`;
        volumes.slice(0, 3).forEach(vol => {
            const volUsed = parseInt(vol.size?.used_byte || 0);
            const volTotal = parseInt(vol.size?.total_byte || 0);
            const volPercent = volTotal > 0 ? Math.round((volUsed / volTotal) * 100) : 0;
            const volName = (vol.name || "Volume").slice(0, 12).padEnd(12);
            o += `  ${volName} ${progressBar(volPercent, 8)} ${volPercent}%\n`;
        });
    }
    
    if (pools.length > 0) {
        o += `\nPools: ${pools.length}\n`;
    }
    
    o += `\n🌐 NETWORK\n`;
    o += `↓ ${fmtBytes(networkRx)}/s ↑ ${fmtBytes(networkTx)}/s\n`;
    
    o += `\n🔗 Tap: Open DSM │ Long: Options`;
    
    return o;
}

// ============================================================================
// Event Handlers
// ============================================================================

aio.onTap = function() {
    const config = getConfig();
    const baseURL = getBaseURL(config);
    aio.open(baseURL);
};

aio.onLongTap = function() {
    const config = getConfig();
    const store = aio.storage.get("syno") || {};
    
    aio.menu([
        "📊 Toggle Compact/Full Mode",
        "🔄 Refresh",
        "🔐 Change Credentials",
        "🔌 Logout Session",
        "⚙️ Settings",
        "❌ Cancel"
    ], async (index) => {
        switch(index) {
            case 0:
                store.mode = store.mode === "compact" ? "full" : "compact";
                aio.storage.set("syno", store);
                aio.refresh();
                break;
            case 1:
                aio.toast("Refreshing...");
                aio.refresh();
                break;
            case 2:
                aio.toast("Edit credentials in config");
                break;
            case 3:
                aio.confirm("Logout current session?", () => {
                    aio.storage.set("syno_session", null);
                    aio.toast("Session cleared");
                    aio.refresh();
                });
                break;
            case 4:
                showSettingsMenu(config);
                break;
        }
    });
};

function showSettingsMenu(config) {
    aio.menu([
        `🌐 NAS IP: ${config.ip}`,
        `🔌 Port: ${config.port}`,
        `🔒 HTTPS: ${config.useHTTPS ? "Yes" : "No"}`,
        "❌ Cancel"
    ], (index) => {
        aio.toast("Edit settings in config");
    });
}

// ============================================================================
// Initialize
// ============================================================================

main();


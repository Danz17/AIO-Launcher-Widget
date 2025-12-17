// ============================================================================
// Synology Surveillance Station Widget for AIO Launcher
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
    const stored = aio.storage.get("surv_config") || {};
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

function fmtDuration(seconds) {
    if (!seconds) return "0s";
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
}

// ============================================================================
// Synology Surveillance API Functions
// ============================================================================

async function synoLogin(config) {
    const baseURL = getBaseURL(config);
    const session = aio.storage.get("syno_session") || {};
    
    // Check if session is still valid
    if (session.sid && session.expires && Date.now() < session.expires) {
        return session.sid;
    }
    
    try {
        const url = `${baseURL}/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=${encodeURIComponent(config.username)}&passwd=${encodeURIComponent(config.password)}&session=SurveillanceStation&format=sid`;
        const response = await fetch(url);
        const data = await response.json();
        
        if (data.success && data.data && data.data.sid) {
            const sid = data.data.sid;
            aio.storage.set("syno_session", {
                sid: sid,
                expires: Date.now() + (20 * 60 * 1000)
            });
            return sid;
        }
        return null;
    } catch (e) {
        console.error("Surveillance login error:", e);
        return null;
    }
}

async function survRequest(method, params, config) {
    const sid = await synoLogin(config);
    if (!sid) return null;
    
    const baseURL = getBaseURL(config);
    const queryParams = new URLSearchParams({
        api: "SYNO.SurveillanceStation.Camera",
        version: "9",
        method: method,
        _sid: sid,
        ...params
    });
    
    try {
        const url = `${baseURL}/webapi/entry.cgi?${queryParams.toString()}`;
        const response = await fetch(url);
        const data = await response.json();
        return data.success ? data.data : null;
    } catch (e) {
        console.error(`Surveillance API error (${method}):`, e);
        return null;
    }
}

async function getCameras(config) {
    return await survRequest("List", { privCamType: 1 }, config);
}

async function getEvents(config, limit = 10) {
    const sid = await synoLogin(config);
    if (!sid) return null;
    
    const baseURL = getBaseURL(config);
    const queryParams = new URLSearchParams({
        api: "SYNO.SurveillanceStation.Event",
        version: "1",
        method: "List",
        _sid: sid,
        limit: limit.toString(),
        offset: "0"
    });
    
    try {
        const url = `${baseURL}/webapi/entry.cgi?${queryParams.toString()}`;
        const response = await fetch(url);
        const data = await response.json();
        return data.success ? data.data : null;
    } catch (e) {
        return null;
    }
}

async function getInfo(config) {
    const sid = await synoLogin(config);
    if (!sid) return null;
    
    const baseURL = getBaseURL(config);
    const queryParams = new URLSearchParams({
        api: "SYNO.SurveillanceStation.Info",
        version: "1",
        method: "GetInfo",
        _sid: sid
    });
    
    try {
        const url = `${baseURL}/webapi/entry.cgi?${queryParams.toString()}`;
        const response = await fetch(url);
        const data = await response.json();
        return data.success ? data.data : null;
    } catch (e) {
        return null;
    }
}

// ============================================================================
// Main Widget Function
// ============================================================================

async function main() {
    const config = getConfig();
    const store = aio.storage.get("surv") || {
        mode: "full"
    };
    
    const mode = store.mode || "full";
    
    // Fetch data
    const [camerasData, eventsData, infoData] = await Promise.all([
        getCameras(config),
        getEvents(config, 5),
        getInfo(config)
    ]);
    
    if (!camerasData) {
        return "❌ Connection failed\n\nCheck IP/credentials\nLong press for options";
    }
    
    const cameras = camerasData.cameras || [];
    const events = eventsData?.events || [];
    const info = infoData || {};
    
    // Process cameras
    const onlineCameras = cameras.filter(c => c.status === 1).length;
    const offlineCameras = cameras.length - onlineCameras;
    const recordingCameras = cameras.filter(c => c.recStatus === 1).length;
    
    // Process events (motion detection)
    const recentEvents = events.filter(e => {
        const eventTime = parseInt(e.startTime) * 1000;
        const oneHourAgo = Date.now() - (60 * 60 * 1000);
        return eventTime > oneHourAgo;
    });
    
    // Storage info
    const storageUsed = info.storageUsed || 0;
    const storageTotal = info.storageTotal || 0;
    const storagePercent = storageTotal > 0 ? Math.round((storageUsed / storageTotal) * 100) : 0;
    
    // Generate output
    let o = "";
    
    if (mode === "compact") {
        o += `📹 ${onlineCameras}/${cameras.length} Online\n`;
        o += `🔴 ${recordingCameras} Recording\n`;
        o += `⚠️ ${recentEvents.length} Events (1h)\n`;
        o += `💾 ${storagePercent}% Used\n`;
        o += `\nTap: Surveillance │ Long: Options`;
        return o;
    }
    
    // Full mode
    o += `📹 Surveillance Station\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    
    o += `\n📷 CAMERAS\n`;
    o += `Online: ${onlineCameras} │ Offline: ${offlineCameras}\n`;
    o += `Recording: ${recordingCameras}\n`;
    
    if (cameras.length > 0) {
        o += `\nCamera List:\n`;
        cameras.slice(0, 5).forEach(cam => {
            const status = cam.status === 1 ? "🟢" : "🔴";
            const rec = cam.recStatus === 1 ? "🔴" : "⚪";
            const name = (cam.name || "Camera").slice(0, 15).padEnd(15);
            o += `${status} ${rec} ${name}\n`;
        });
        if (cameras.length > 5) {
            o += `  +${cameras.length - 5} more\n`;
        }
    }
    
    o += `\n⚠️ RECENT EVENTS\n`;
    if (recentEvents.length > 0) {
        recentEvents.slice(0, 3).forEach(event => {
            const eventTime = new Date(parseInt(event.startTime) * 1000);
            const timeStr = eventTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const camName = (event.cameraName || "Camera").slice(0, 12);
            const eventType = event.eventType === 1 ? "Motion" : "Other";
            o += `  ${timeStr} ${camName} (${eventType})\n`;
        });
    } else {
        o += `  No events in last hour\n`;
    }
    
    o += `\n💾 STORAGE\n`;
    o += `Used: ${fmtBytes(storageUsed)} / ${fmtBytes(storageTotal)} (${storagePercent}%)\n`;
    
    o += `\n🔗 Tap: Open Surveillance │ Long: Options`;
    
    return o;
}

// ============================================================================
// Event Handlers
// ============================================================================

aio.onTap = function() {
    const config = getConfig();
    const baseURL = getBaseURL(config);
    aio.open(`${baseURL}/webapi/entry.cgi?api=SYNO.SurveillanceStation.Application&version=1&method=Launch&_sid=${aio.storage.get("syno_session")?.sid || ""}`);
};

aio.onLongTap = function() {
    const config = getConfig();
    const store = aio.storage.get("surv") || {};
    
    aio.menu([
        "📊 Toggle Compact/Full Mode",
        "🔄 Refresh",
        "🔐 Change Credentials",
        "⚙️ Settings",
        "❌ Cancel"
    ], async (index) => {
        switch(index) {
            case 0:
                store.mode = store.mode === "compact" ? "full" : "compact";
                aio.storage.set("surv", store);
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


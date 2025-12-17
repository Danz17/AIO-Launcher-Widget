// ============================================================================
// MikroTik Router Monitoring Widget for AIO Launcher
// ============================================================================

// Configuration - can be overridden via storage
const DEFAULT_CONFIG = {
    ip: "10.1.1.1",
    username: "admin",
    password: "admin123",
    dailyLimitGB: 10,
    monthlyLimitGB: 100,
    lowSignalThreshold: -85,
    highCpuThreshold: 80,
    highMemThreshold: 85,
    pingHost: "8.8.8.8",
    refreshHistory: 30,
    maxClientsShow: 6,
    retryAttempts: 3,
    retryDelay: 1000
};

// ============================================================================
// Utility Functions
// ============================================================================

function getConfig() {
    const stored = aio.storage.get("mt_config") || {};
    return { ...DEFAULT_CONFIG, ...stored };
}

function getAuth(config) {
    const creds = aio.storage.get("mt_credentials");
    if (creds && creds.username && creds.password) {
        return "Basic " + btoa(`${creds.username}:${creds.password}`);
    }
    return "Basic " + btoa(`${config.username}:${config.password}`);
}

function formatDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return {
        day: `${year}-${month}-${day}`,
        month: `${year}-${month}`
    };
}

function fmt(bps) {
    if (!bps || bps < 0) return "0";
    if (bps >= 1e9) return (bps/1e9).toFixed(1) + "G";
    if (bps >= 1e6) return (bps/1e6).toFixed(1) + "M";
    if (bps >= 1e3) return (bps/1e3).toFixed(0) + "K";
    return bps.toFixed(0);
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
    if (h > 24) return Math.floor(h/24) + "d" + (h%24) + "h";
    if (h > 0) return h + "h" + m + "m";
    return m + "m";
}

function parseUptime(str) {
    if (!str) return 0;
    let secs = 0;
    const w = str.match(/(\d+)w/); if (w) secs += parseInt(w[1]) * 604800;
    const d = str.match(/(\d+)d/); if (d) secs += parseInt(d[1]) * 86400;
    const h = str.match(/(\d+)h/); if (h) secs += parseInt(h[1]) * 3600;
    const m = str.match(/(\d+)m/); if (m) secs += parseInt(m[1]) * 60;
    const s = str.match(/(\d+)s/); if (s) secs += parseInt(s[1]);
    return secs;
}

function miniGraph(history, width = 15) {
    const bars = "▁▂▃▄▅▆▇█";
    if (!history || history.length === 0) return bars[0].repeat(width);
    const max = Math.max(...history, 1);
    return history.slice(-width).map(v => bars[Math.min(7, Math.floor((v/max) * 7))] || bars[0]).join("");
}

function progressBar(percent, width = 10) {
    const filled = Math.round((percent / 100) * width);
    return "█".repeat(filled) + "░".repeat(width - filled);
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

// ============================================================================
// API Functions with Retry Logic
// ============================================================================

async function get(endpoint, config, retries = null) {
    const maxRetries = retries !== null ? retries : config.retryAttempts;
    const auth = getAuth(config);
    const url = `http://${config.ip}/rest${endpoint}`;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            const response = await fetch(url, {
                headers: { "Authorization": auth }
            });

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }

            const data = await response.json();
            return data;
        } catch (e) {
            if (attempt === maxRetries) {
                console.error(`API GET failed after ${maxRetries + 1} attempts:`, e);
                return null;
            }
            await new Promise(resolve => setTimeout(resolve, config.retryDelay));
        }
    }
    return null;
}

async function post(endpoint, data, config, retries = null) {
    const maxRetries = retries !== null ? retries : config.retryAttempts;
    const auth = getAuth(config);
    const url = `http://${config.ip}/rest${endpoint}`;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            const response = await fetch(url, {
                method: "POST",
                headers: { 
                    "Authorization": auth, 
                    "Content-Type": "application/json" 
                },
                body: JSON.stringify(data)
            });

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }

            const result = await response.json();
            return result;
        } catch (e) {
            if (attempt === maxRetries) {
                console.error(`API POST failed after ${maxRetries + 1} attempts:`, e);
                return null;
            }
            await new Promise(resolve => setTimeout(resolve, config.retryDelay));
        }
    }
    return null;
}

// ============================================================================
// Data Processing Functions
// ============================================================================

function calcSpeed(iface, prevRx, prevTx, dt) {
    if (!iface || dt <= 0 || dt > 60) {
        return { 
            down: 0, 
            up: 0, 
            totalDown: iface?.["rx-byte"] || 0, 
            totalUp: iface?.["tx-byte"] || 0 
        };
    }

    const prevRxBytes = prevRx || 0;
    const prevTxBytes = prevTx || 0;
    const currRxBytes = iface["rx-byte"] || 0;
    const currTxBytes = iface["tx-byte"] || 0;

    const down = Math.max((currRxBytes - prevRxBytes) / dt, 0);
    const up = Math.max((currTxBytes - prevTxBytes) / dt, 0);

    return { 
        down, 
        up,
        totalDown: currRxBytes,
        totalUp: currTxBytes
    };
}

function processClients(clientList, dhcpLeases) {
    if (!Array.isArray(clientList)) return [];
    if (!Array.isArray(dhcpLeases)) dhcpLeases = [];

    return clientList.map(c => {
        if (c?.user) {
            // Hotspot client
            return {
                id: c["mac-address"] || c.user,
                name: c.user || "Unknown",
                mac: c["mac-address"] || "",
                ip: c.address || "",
                down: parseInt(c["bytes-in"]) || 0,
                up: parseInt(c["bytes-out"]) || 0,
                uptime: c.uptime || "",
                type: "hotspot"
            };
        } else {
            // Wireless client
            const mac = c["mac-address"] || "";
            const lease = dhcpLeases.find(l => l?.["mac-address"] === mac);
            return {
                id: mac || `unknown_${Math.random()}`,
                name: lease?.["host-name"] || mac?.slice(-8) || "Unknown",
                mac: mac,
                ip: lease?.address || "",
                signal: c["signal-strength"] || -100,
                txRate: c["tx-rate"] || 0,
                rxRate: c["rx-rate"] || 0,
                type: "wireless"
            };
        }
    }).filter(c => c.id); // Remove invalid entries
}

// ============================================================================
// Main Widget Function
// ============================================================================

async function main() {
    const config = getConfig();
    const WEBFIG_URL = `http://${config.ip}/webfig/`;

    const store = aio.storage.get("mt") || { 
        t: 0, 
        hist: { down: [], up: [], signal: [], latency: [] },
        usage: { daily: {}, monthly: {} },
        clients: [],
        alerts: {},
        mode: "full"
    };

    const now = Date.now();
    const dt = store.t ? (now - store.t) / 1000 : 0;
    const dateKey = formatDate(new Date());
    const mode = store.mode || "full";

    // Fetch all data in parallel
    const [
        ifaces, 
        res, 
        health, 
        routes, 
        dhcpLeases, 
        hotspotActive, 
        regTable, 
        lteMonitor, 
        pingResult
    ] = await Promise.all([
        get("/interface", config),
        get("/system/resource", config),
        get("/system/health", config),
        get("/ip/route?active=true", config),
        get("/ip/dhcp-server/lease", config),
        get("/ip/hotspot/active", config),
        get("/interface/wireless/registration-table", config),
        get("/interface/lte/monitor?once=&numbers=0", config),
        post("/ping", { address: config.pingHost, count: "1" }, config)
    ]);

    // Check if connection failed
    if (!ifaces || !Array.isArray(ifaces)) {
        return "❌ Connection failed\n\nTap to open WebFig\nLong press for options";
    }

    // Find interfaces safely
    const lte = Array.isArray(ifaces) ? ifaces.find(i => i?.name === "lte1") : null;
    const wifiWan = Array.isArray(ifaces) ? ifaces.find(i => i?.name === "wifi1-wan") : null;
    const wifiHotspot = Array.isArray(ifaces) ? ifaces.find(i => i?.name === "wifi2-hotspot") : null;
    const lteInfo = (Array.isArray(lteMonitor) && lteMonitor.length > 0) ? lteMonitor[0] : null;

    // Calculate speeds
    const lteSpeed = calcSpeed(lte, store.lteRx, store.lteTx, dt);
    const wanSpeed = calcSpeed(wifiWan, store.wanRx, store.wanTx, dt);
    const hotspotSpeed = calcSpeed(wifiHotspot, store.hsRx, store.hsTx, dt);

    // Determine active WAN
    let activeWan = "None";
    let totalDown = 0, totalUp = 0;
    if (lte?.running === "true" && lteSpeed.down > wanSpeed.down) {
        activeWan = "LTE";
        totalDown = lteSpeed.down;
        totalUp = lteSpeed.up;
    } else if (wifiWan?.running === "true") {
        activeWan = "WiFi-WAN";
        totalDown = wanSpeed.down;
        totalUp = wanSpeed.up;
    }

    // Update history
    const hist = store.hist || { down: [], up: [], signal: [], latency: [] };
    hist.down.push(totalDown * 8);
    hist.up.push(totalUp * 8);
    if (hist.down.length > config.refreshHistory) hist.down.shift();
    if (hist.up.length > config.refreshHistory) hist.up.shift();

    const currentSignal = parseInt(lteInfo?.rssi || lteInfo?.["signal-strength"] || -100);
    hist.signal.push(currentSignal);
    if (hist.signal.length > config.refreshHistory) hist.signal.shift();

    const latency = pingResult?.[0]?.time ? parseInt(pingResult[0].time) : null;
    if (latency !== null && !isNaN(latency)) {
        hist.latency.push(latency);
        if (hist.latency.length > config.refreshHistory) hist.latency.shift();
    }

    // Update usage statistics
    const usage = store.usage || { daily: {}, monthly: {} };
    const bytesDown = dt > 0 ? totalDown * dt : 0;
    const bytesUp = dt > 0 ? totalUp * dt : 0;

    if (!usage.daily[dateKey.day]) {
        usage.daily[dateKey.day] = { down: 0, up: 0 };
    }
    usage.daily[dateKey.day].down += bytesDown;
    usage.daily[dateKey.day].up += bytesUp;

    if (!usage.monthly[dateKey.month]) {
        usage.monthly[dateKey.month] = { down: 0, up: 0 };
    }
    usage.monthly[dateKey.month].down += bytesDown;
    usage.monthly[dateKey.month].up += bytesUp;

    const todayUsage = usage.daily[dateKey.day] || { down: 0, up: 0 };
    const monthUsage = usage.monthly[dateKey.month] || { down: 0, up: 0 };
    const todayTotal = todayUsage.down + todayUsage.up;
    const monthTotal = monthUsage.down + monthUsage.up;

    // Process clients
    const clientList = (Array.isArray(hotspotActive) && hotspotActive.length > 0) 
        ? hotspotActive 
        : (Array.isArray(regTable) ? regTable : []);
    const leases = Array.isArray(dhcpLeases) ? dhcpLeases : [];
    const currentClients = processClients(clientList, leases);
    const topUsers = [...currentClients].sort((a, b) => 
        ((b.down || 0) + (b.up || 0)) - ((a.down || 0) + (a.up || 0))
    );

    // Handle alerts
    const alerts = store.alerts || {};
    const prevClients = store.clients || [];
    const prevIds = prevClients.map(c => c?.id).filter(Boolean);
    const currIds = currentClients.map(c => c?.id).filter(Boolean);

    // Client connection/disconnection notifications
    currentClients.filter(c => !prevIds.includes(c.id)).forEach(c => {
        aio.notify("📱 Connected", `${c.name} joined`);
    });
    prevClients.filter(c => !currIds.includes(c.id)).forEach(c => {
        aio.notify("📴 Disconnected", `${c.name} left`);
    });

    // Usage limit alerts
    if (todayTotal >= config.dailyLimitGB * 1e9 && !alerts[`daily_${dateKey.day}`]) {
        aio.notify("⚠️ Daily Limit", `Usage exceeded ${config.dailyLimitGB}GB today`);
        alerts[`daily_${dateKey.day}`] = true;
    }

    if (monthTotal >= config.monthlyLimitGB * 1e9 && !alerts[`monthly_${dateKey.month}`]) {
        aio.notify("⚠️ Monthly Limit", `Usage exceeded ${config.monthlyLimitGB}GB this month`);
        alerts[`monthly_${dateKey.month}`] = true;
    }

    // Signal alert
    const signalAlertKey = `signal_${Math.floor(now / 300000)}`;
    if (currentSignal <= config.lowSignalThreshold && !alerts[signalAlertKey] && lte?.running === "true") {
        aio.notify("📉 Low Signal", `LTE signal: ${currentSignal}dBm`);
        alerts[signalAlertKey] = true;
    }

    // CPU alert
    const cpu = res?.["cpu-load"] || 0;
    const cpuAlertKey = `cpu_${Math.floor(now / 300000)}`;
    if (cpu >= config.highCpuThreshold && !alerts[cpuAlertKey]) {
        aio.notify("🔥 High CPU", `Router CPU at ${cpu}%`);
        alerts[cpuAlertKey] = true;
    }

    // Memory alert
    const mem = res ? Math.round((res["total-memory"] - res["free-memory"]) / res["total-memory"] * 100) : 0;
    const memAlertKey = `mem_${Math.floor(now / 300000)}`;
    if (mem >= config.highMemThreshold && !alerts[memAlertKey]) {
        aio.notify("💾 High Memory", `Router memory at ${mem}%`);
        alerts[memAlertKey] = true;
    }

    // System info
    const uptime = res?.uptime || "?";
    const boardTemp = health?.find(h => h?.name === "board-temperature1")?.value || 
                      health?.find(h => h?.name === "temperature")?.value || null;

    const activeLeases = leases.filter(l => l?.status === "bound").length;
    const totalLeases = leases.length;

    // Save state
    aio.storage.set("mt", {
        t: now,
        lteRx: lte?.["rx-byte"], 
        lteTx: lte?.["tx-byte"],
        wanRx: wifiWan?.["rx-byte"], 
        wanTx: wifiWan?.["tx-byte"],
        hsRx: wifiHotspot?.["rx-byte"], 
        hsTx: wifiHotspot?.["tx-byte"],
        hist, 
        usage, 
        clients: currentClients, 
        alerts, 
        mode
    });

    // Generate output
    let o = "";

    if (mode === "compact") {
        o += `📡 ${activeWan} ↓${fmt(totalDown*8)} ↑${fmt(totalUp*8)}`;
        if (lte?.running === "true") o += ` │ ${currentSignal}dBm`;
        o += `\n👥 ${currentClients.length} │ 📊 ${fmtBytes(todayTotal)}`;
        o += `\n${miniGraph(hist.down, 20)}`;
        o += `\n\nTap: WebFig │ Long: Options`;
        return o;
    }

    // Full mode
    const tempStr = boardTemp ? ` │ 🌡${boardTemp}°` : "";
    o += `🖥 CPU ${progressBar(cpu, 5)} ${cpu}% │ RAM ${mem}%${tempStr}\n`;
    o += `⏱ ${uptime.match(/\d+[wdhm]/g)?.slice(0,2).join("") || uptime} │ 🌐 ${activeWan}\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;

    if (lte) {
        const status = lte.running === "true" ? "🟢" : "🔴";
        const sigIcon = signalIcon(currentSignal);
        const sigBar = signalBar(currentSignal);
        const operator = lteInfo?.operator || "";
        const tech = lteInfo?.["access-technology"] || "";
        o += `📡 LTE ${status} ${sigIcon} ${sigBar} ${currentSignal}dBm\n`;
        if (operator) o += `   ${operator} ${tech}\n`;
        o += `   ↓${fmt(lteSpeed.down*8)} ↑${fmt(lteSpeed.up*8)}\n`;
    }

    if (wifiWan) {
        const status = wifiWan.running === "true" ? "🟢" : "🔴";
        o += `📶 WiFi-WAN ${status}\n`;
        o += `   ↓${fmt(wanSpeed.down*8)} ↑${fmt(wanSpeed.up*8)}\n`;
    }

    if (wifiHotspot) {
        const status = wifiHotspot.running === "true" ? "🟢" : "🔴";
        o += `📻 Hotspot ${status} │ 👥 ${currentClients.length}\n`;
        o += `   ↓${fmt(hotspotSpeed.down*8)} ↑${fmt(hotspotSpeed.up*8)}\n`;
    }

    o += `\n📊 GRAPHS\n`;
    o += `Speed ↓ ${miniGraph(hist.down)} ${fmt(Math.max(...hist.down, 0))}\n`;
    o += `Speed ↑ ${miniGraph(hist.up)} ${fmt(Math.max(...hist.up, 0))}\n`;
    if (lte && hist.signal.length > 0) {
        const sigGraph = hist.signal.map(s => 100 + s);
        o += `Signal  ${miniGraph(sigGraph)} ${currentSignal}dBm\n`;
    }
    if (hist.latency.length > 0) {
        const avgLatency = Math.round(hist.latency.reduce((a,b) => a+b, 0) / hist.latency.length);
        o += `Latency ${miniGraph(hist.latency)} ${avgLatency}ms\n`;
    }

    const dailyPercent = Math.min(100, (todayTotal / (config.dailyLimitGB * 1e9)) * 100);
    const monthPercent = Math.min(100, (monthTotal / (config.monthlyLimitGB * 1e9)) * 100);
    o += `\n📈 DATA USAGE\n`;
    o += `Today ${progressBar(dailyPercent, 8)} ${fmtBytes(todayTotal)}/${config.dailyLimitGB}GB\n`;
    o += `Month ${progressBar(monthPercent, 8)} ${fmtBytes(monthTotal)}/${config.monthlyLimitGB}GB\n`;

    o += `\n👥 CLIENTS (${currentClients.length}) │ DHCP ${activeLeases}/${totalLeases}\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;

    for (const c of topUsers.slice(0, config.maxClientsShow)) {
        const name = (c.name || "?").slice(0, 9).padEnd(9);
        if (c.type === "hotspot") {
            const total = fmtBytes(c.down + c.up);
            const time = c.uptime ? fmtDuration(parseUptime(c.uptime)) : "";
            o += `• ${name} ${total.padStart(7)} ${time}\n`;
        } else {
            const sig = c.signal || -100;
            const bar = signalBar(sig);
            o += `• ${name} ${bar} ${sig}dBm\n`;
        }
    }

    if (currentClients.length > config.maxClientsShow) {
        o += `  +${currentClients.length - config.maxClientsShow} more\n`;
    }

    o += `\n🔗 Tap: WebFig │ Long: Options`;

    return o;
}

// ============================================================================
// Event Handlers
// ============================================================================

aio.onTap = function() {
    const config = getConfig();
    aio.open(`http://${config.ip}/webfig/`);
};

aio.onLongTap = function() {
    const config = getConfig();
    const store = aio.storage.get("mt") || {};

    aio.menu([
        "📊 Toggle Compact/Full Mode",
        "⚙️ Settings",
        "🔐 Change Credentials",
        "🔄 Reboot Router",
        "📡 Disable LTE",
        "📡 Enable LTE",
        "📻 Disable Hotspot",
        "📻 Enable Hotspot",
        "🗑️ Reset Usage Stats",
        "❌ Cancel"
    ], async (index) => {
        switch(index) {
            case 0:
                store.mode = store.mode === "compact" ? "full" : "compact";
                aio.storage.set("mt", store);
                aio.refresh();
                break;
            case 1:
                showSettingsMenu(config);
                break;
            case 2:
                showCredentialsMenu(config);
                break;
            case 3:
                aio.confirm("Reboot router?", async () => {
                    const result = await post("/system/reboot", {}, config);
                    if (result !== null) {
                        aio.toast("Router rebooting...");
                    } else {
                        aio.toast("Failed to reboot router");
                    }
                });
                break;
            case 4:
                const disableLte = await post("/interface/disable", { numbers: "lte1" }, config);
                if (disableLte !== null) {
                    aio.toast("LTE disabled");
                    aio.refresh();
                } else {
                    aio.toast("Failed to disable LTE");
                }
                break;
            case 5:
                const enableLte = await post("/interface/enable", { numbers: "lte1" }, config);
                if (enableLte !== null) {
                    aio.toast("LTE enabled");
                    aio.refresh();
                } else {
                    aio.toast("Failed to enable LTE");
                }
                break;
            case 6:
                const disableHotspot = await post("/interface/disable", { numbers: "wifi2-hotspot" }, config);
                if (disableHotspot !== null) {
                    aio.toast("Hotspot disabled");
                    aio.refresh();
                } else {
                    aio.toast("Failed to disable hotspot");
                }
                break;
            case 7:
                const enableHotspot = await post("/interface/enable", { numbers: "wifi2-hotspot" }, config);
                if (enableHotspot !== null) {
                    aio.toast("Hotspot enabled");
                    aio.refresh();
                } else {
                    aio.toast("Failed to enable hotspot");
                }
                break;
            case 8:
                aio.confirm("Reset usage stats?", () => {
                    store.usage = { daily: {}, monthly: {} };
                    store.hist = { down: [], up: [], signal: [], latency: [] };
                    aio.storage.set("mt", store);
                    aio.toast("Stats reset");
                    aio.refresh();
                });
                break;
        }
    });
};

function showSettingsMenu(config) {
    aio.menu([
        `📊 Daily Limit: ${config.dailyLimitGB}GB`,
        `📊 Monthly Limit: ${config.monthlyLimitGB}GB`,
        `📉 Low Signal Threshold: ${config.lowSignalThreshold}dBm`,
        `🔥 High CPU Threshold: ${config.highCpuThreshold}%`,
        `💾 High Memory Threshold: ${config.highMemThreshold}%`,
        `🌐 Router IP: ${config.ip}`,
        `🏓 Ping Host: ${config.pingHost}`,
        "❌ Cancel"
    ], (index) => {
        // Note: Full settings editing would require input dialogs
        // This is a placeholder for the settings menu structure
        aio.toast("Settings editing coming soon");
    });
}

function showCredentialsMenu(config) {
    aio.menu([
        "📝 Enter New Credentials",
        "🗑️ Clear Stored Credentials",
        "❌ Cancel"
    ], (index) => {
        switch(index) {
            case 0:
                // Note: Would need input dialogs for username/password
                // For now, show instructions
                aio.toast("Edit credentials in script or use storage API");
                break;
            case 1:
                aio.confirm("Clear stored credentials?", () => {
                    aio.storage.set("mt_credentials", null);
                    aio.toast("Credentials cleared");
                });
                break;
        }
    });
}

// ============================================================================
// Initialize
// ============================================================================

main();
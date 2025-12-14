const IP = "10.1.1.1";
const auth = "Basic " + btoa("admin:admin123");
const WEBFIG_URL = `http://${IP}/webfig/`;

const CONFIG = {
    dailyLimitGB: 10,
    monthlyLimitGB: 100,
    lowSignalThreshold: -85,
    highCpuThreshold: 80,
    highMemThreshold: 85,
    pingHost: "8.8.8.8",
    refreshHistory: 30,
    maxClientsShow: 6
};

async function get(endpoint) {
    try {
        const r = await fetch(`http://${IP}/rest${endpoint}`, {
            headers: { "Authorization": auth }
        });
        return r.json();
    } catch(e) { return null; }
}

async function post(endpoint, data) {
    try {
        const r = await fetch(`http://${IP}/rest${endpoint}`, {
            method: "POST",
            headers: { "Authorization": auth, "Content-Type": "application/json" },
            body: JSON.stringify(data)
        });
        return r.json();
    } catch(e) { return null; }
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

function getDateKey() {
    const d = new Date();
    return {
        day: `${d.getFullYear()}-${d.getMonth()+1}-${d.getDate()}`,
        month: `${d.getFullYear()}-${d.getMonth()+1}`
    };
}

async function main() {
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
    const dateKey = getDateKey();
    const mode = store.mode || "full";

    const [ifaces, res, health, routes, dhcpLeases, hotspotActive, regTable, lteMonitor, pingResult] = await Promise.all([
        get("/interface"),
        get("/system/resource"),
        get("/system/health"),
        get("/ip/route?active=true"),
        get("/ip/dhcp-server/lease"),
        get("/ip/hotspot/active"),
        get("/interface/wireless/registration-table"),
        get("/interface/lte/monitor?once=&numbers=0"),
        post("/ping", { address: CONFIG.pingHost, count: "1" })
    ]);

    if (!ifaces) return "❌ Connection failed\n\nTap to open WebFig\nLong press for options";

    const lte = ifaces.find(i => i.name === "lte1");
    const wifiWan = ifaces.find(i => i.name === "wifi1-wan");
    const wifiHotspot = ifaces.find(i => i.name === "wifi2-hotspot");
    const lteInfo = lteMonitor?.[0] || null;

    const calcSpeed = (iface, prevRx, prevTx) => {
        if (!iface || dt <= 0 || dt > 60) return { down: 0, up: 0, totalDown: iface?.["rx-byte"] || 0, totalUp: iface?.["tx-byte"] || 0 };
        const down = ((iface["rx-byte"] || 0) - (prevRx || 0)) / dt;
        const up = ((iface["tx-byte"] || 0) - (prevTx || 0)) / dt;
        return { 
            down: Math.max(down, 0), 
            up: Math.max(up, 0),
            totalDown: iface["rx-byte"] || 0,
            totalUp: iface["tx-byte"] || 0
        };
    };

    const lteSpeed = calcSpeed(lte, store.lteRx, store.lteTx);
    const wanSpeed = calcSpeed(wifiWan, store.wanRx, store.wanTx);
    const hotspotSpeed = calcSpeed(wifiHotspot, store.hsRx, store.hsTx);

    let activeWan = "None";
    let totalDown = 0, totalUp = 0;
    if (lteSpeed.down > wanSpeed.down && lte?.running === "true") {
        activeWan = "LTE";
        totalDown = lteSpeed.down;
        totalUp = lteSpeed.up;
    } else if (wifiWan?.running === "true") {
        activeWan = "WiFi-WAN";
        totalDown = wanSpeed.down;
        totalUp = wanSpeed.up;
    }

    const hist = store.hist || { down: [], up: [], signal: [], latency: [] };
    hist.down.push(totalDown * 8);
    hist.up.push(totalUp * 8);
    if (hist.down.length > CONFIG.refreshHistory) hist.down.shift();
    if (hist.up.length > CONFIG.refreshHistory) hist.up.shift();

    const currentSignal = parseInt(lteInfo?.rssi || lteInfo?.["signal-strength"]) || -100;
    hist.signal.push(currentSignal);
    if (hist.signal.length > CONFIG.refreshHistory) hist.signal.shift();

    const latency = pingResult?.[0]?.time ? parseInt(pingResult[0].time) : null;
    if (latency) {
        hist.latency.push(latency);
        if (hist.latency.length > CONFIG.refreshHistory) hist.latency.shift();
    }

    const usage = store.usage || { daily: {}, monthly: {} };
    const bytesDown = dt > 0 ? totalDown * dt : 0;
    const bytesUp = dt > 0 ? totalUp * dt : 0;

    if (!usage.daily[dateKey.day]) usage.daily = { [dateKey.day]: { down: 0, up: 0 } };
    usage.daily[dateKey.day].down += bytesDown;
    usage.daily[dateKey.day].up += bytesUp;

    if (!usage.monthly[dateKey.month]) usage.monthly = { [dateKey.month]: { down: 0, up: 0 } };
    usage.monthly[dateKey.month].down += bytesDown;
    usage.monthly[dateKey.month].up += bytesUp;

    const todayUsage = usage.daily[dateKey.day] || { down: 0, up: 0 };
    const monthUsage = usage.monthly[dateKey.month] || { down: 0, up: 0 };
    const todayTotal = todayUsage.down + todayUsage.up;
    const monthTotal = monthUsage.down + monthUsage.up;

    const clientList = hotspotActive.length > 0 ? hotspotActive : regTable;
    const leases = dhcpLeases || [];

    const currentClients = clientList.map(c => {
        if (c.user) {
            return {
                id: c["mac-address"] || c.user,
                name: c.user,
                mac: c["mac-address"],
                ip: c.address,
                down: parseInt(c["bytes-in"]) || 0,
                up: parseInt(c["bytes-out"]) || 0,
                uptime: c.uptime,
                type: "hotspot"
            };
        } else {
            const mac = c["mac-address"];
            const lease = leases.find(l => l["mac-address"] === mac);
            return {
                id: mac,
                name: lease?.["host-name"] || mac?.slice(-8) || "Unknown",
                mac: mac,
                ip: lease?.address,
                signal: c["signal-strength"],
                txRate: c["tx-rate"],
                rxRate: c["rx-rate"],
                type: "wireless"
            };
        }
    });

    const topUsers = [...currentClients].sort((a, b) => ((b.down || 0) + (b.up || 0)) - ((a.down || 0) + (a.up || 0)));

    const alerts = store.alerts || {};
    const prevClients = store.clients || [];
    const prevIds = prevClients.map(c => c.id);
    const currIds = currentClients.map(c => c.id);

    currentClients.filter(c => !prevIds.includes(c.id)).forEach(c => {
        aio.notify("📱 Connected", `${c.name} joined`);
    });
    prevClients.filter(c => !currIds.includes(c.id)).forEach(c => {
        aio.notify("📴 Disconnected", `${c.name} left`);
    });

    if (todayTotal >= CONFIG.dailyLimitGB * 1e9 && !alerts[`daily_${dateKey.day}`]) {
        aio.notify("⚠️ Daily Limit", `Usage exceeded ${CONFIG.dailyLimitGB}GB today`);
        alerts[`daily_${dateKey.day}`] = true;
    }

    if (monthTotal >= CONFIG.monthlyLimitGB * 1e9 && !alerts[`monthly_${dateKey.month}`]) {
        aio.notify("⚠️ Monthly Limit", `Usage exceeded ${CONFIG.monthlyLimitGB}GB this month`);
        alerts[`monthly_${dateKey.month}`] = true;
    }

    const signalAlertKey = `signal_${Math.floor(now / 300000)}`;
    if (currentSignal <= CONFIG.lowSignalThreshold && !alerts[signalAlertKey] && lte?.running === "true") {
        aio.notify("📉 Low Signal", `LTE signal: ${currentSignal}dBm`);
        alerts[signalAlertKey] = true;
    }

    const cpu = res?.["cpu-load"] || 0;
    const cpuAlertKey = `cpu_${Math.floor(now / 300000)}`;
    if (cpu >= CONFIG.highCpuThreshold && !alerts[cpuAlertKey]) {
        aio.notify("🔥 High CPU", `Router CPU at ${cpu}%`);
        alerts[cpuAlertKey] = true;
    }

    const mem = res ? Math.round((res["total-memory"] - res["free-memory"]) / res["total-memory"] * 100) : 0;
    const uptime = res?.uptime || "?";
    const boardTemp = health?.find(h => h.name === "board-temperature1")?.value || 
                      health?.find(h => h.name === "temperature")?.value || null;

    const activeLeases = leases.filter(l => l.status === "bound").length;
    const totalLeases = leases.length;

    aio.storage.set("mt", {
        t: now,
        lteRx: lte?.["rx-byte"], lteTx: lte?.["tx-byte"],
        wanRx: wifiWan?.["rx-byte"], wanTx: wifiWan?.["tx-byte"],
        hsRx: wifiHotspot?.["rx-byte"], hsTx: wifiHotspot?.["tx-byte"],
        hist, usage, clients: currentClients, alerts, mode
    });

    let o = "";

    if (mode === "compact") {
        o += `📡 ${activeWan} ↓${fmt(totalDown*8)} ↑${fmt(totalUp*8)}`;
        if (lte?.running === "true") o += ` │ ${currentSignal}dBm`;
        o += `\n👥 ${currentClients.length} │ 📊 ${fmtBytes(todayTotal)}`;
        o += `\n${miniGraph(hist.down, 20)}`;
        o += `\n\nTap: WebFig │ Long: Options`;
        return o;
    }

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
    o += `Speed ↓ ${miniGraph(hist.down)} ${fmt(Math.max(...hist.down,0))}\n`;
    o += `Speed ↑ ${miniGraph(hist.up)} ${fmt(Math.max(...hist.up,0))}\n`;
    if (lte && hist.signal.length > 0) {
        const sigGraph = hist.signal.map(s => 100 + s);
        o += `Signal  ${miniGraph(sigGraph)} ${currentSignal}dBm\n`;
    }
    if (hist.latency.length > 0) {
        const avgLatency = Math.round(hist.latency.reduce((a,b) => a+b, 0) / hist.latency.length);
        o += `Latency ${miniGraph(hist.latency)} ${avgLatency}ms\n`;
    }

    const dailyPercent = Math.min(100, (todayTotal / (CONFIG.dailyLimitGB * 1e9)) * 100);
    const monthPercent = Math.min(100, (monthTotal / (CONFIG.monthlyLimitGB * 1e9)) * 100);
    o += `\n📈 DATA USAGE\n`;
    o += `Today ${progressBar(dailyPercent, 8)} ${fmtBytes(todayTotal)}/${CONFIG.dailyLimitGB}GB\n`;
    o += `Month ${progressBar(monthPercent, 8)} ${fmtBytes(monthTotal)}/${CONFIG.monthlyLimitGB}GB\n`;

    o += `\n👥 CLIENTS (${currentClients.length}) │ DHCP ${activeLeases}/${totalLeases}\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;

    for (const c of topUsers.slice(0, CONFIG.maxClientsShow)) {
        const name = (c.name || "?").slice(0, 9).padEnd(9);
        if (c.type === "hotspot") {
            const total = fmtBytes(c.down + c.up);
            const time = c.uptime ? fmtDuration(parseUptime(c.uptime)) : "";
            o += `• ${name} ${total.padStart(7)} ${time}\n`;
        } else {
            const sig = c.signal || "";
            const bar = signalBar(sig);
            o += `• ${name} ${bar} ${sig}\n`;
        }
    }

    if (currentClients.length > CONFIG.maxClientsShow) {
        o += `  +${currentClients.length - CONFIG.maxClientsShow} more\n`;
    }

    o += `\n🔗 Tap: WebFig │ Long: Options`;

    return o;
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

aio.onTap = function() {
    aio.open(WEBFIG_URL);
};

aio.onLongTap = function() {
    const store = aio.storage.get("mt") || {};

    aio.menu([
        "📊 Toggle Compact/Full Mode",
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
                aio.confirm("Reboot router?", async () => {
                    await post("/system/reboot", {});
                    aio.toast("Router rebooting...");
                });
                break;
            case 2:
                await post("/interface/disable", { numbers: "lte1" });
                aio.toast("LTE disabled");
                aio.refresh();
                break;
            case 3:
                await post("/interface/enable", { numbers: "lte1" });
                aio.toast("LTE enabled");
                aio.refresh();
                break;
            case 4:
                await post("/interface/disable", { numbers: "wifi2-hotspot" });
                aio.toast("Hotspot disabled");
                aio.refresh();
                break;
            case 5:
                await post("/interface/enable", { numbers: "wifi2-hotspot" });
                aio.toast("Hotspot enabled");
                aio.refresh();
                break;
            case 6:
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

main();

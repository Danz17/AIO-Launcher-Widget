// ============================================================================
// Tuya Smart Devices Widget for AIO Launcher
// ============================================================================

// Configuration - can be overridden via storage
const DEFAULT_CONFIG = {
    accessId: "",
    accessSecret: "",
    region: "us", // us, eu, cn, in
    deviceIds: [],
    retryAttempts: 3,
    retryDelay: 1000
};

// ============================================================================
// Utility Functions
// ============================================================================

function getConfig() {
    const stored = aio.storage.get("tuya_config") || {};
    return { ...DEFAULT_CONFIG, ...stored };
}

function getBaseURL(region) {
    const urls = {
        us: "https://openapi.tuyaus.com",
        eu: "https://openapi.tuyaeu.com",
        cn: "https://openapi.tuyacn.com",
        in: "https://openapi.tuyain.com"
    };
    return urls[region] || urls.us;
}

function getDeviceIcon(device) {
    const category = device.category || "";
    if (category.includes("light")) return "💡";
    if (category.includes("switch")) return "🔌";
    if (category.includes("curtain")) return "🪟";
    if (category.includes("thermostat")) return "🌡️";
    if (category.includes("fan")) return "🌀";
    return "📱";
}

function getDeviceStatus(device) {
    const status = device.status || [];
    const online = device.online || false;
    if (!online) return { text: "Offline", icon: "🔴" };
    
    // Check for switch/light status
    const switchStatus = status.find(s => s.code === "switch_1" || s.code === "switch");
    if (switchStatus) {
        return switchStatus.value ? { text: "On", icon: "🟢" } : { text: "Off", icon: "⚪" };
    }
    
    return { text: "Online", icon: "🟢" };
}

// ============================================================================
// Tuya API Functions
// ============================================================================

function generateSign(method, url, timestamp, accessSecret, body = "") {
    // Simplified sign generation - Tuya uses HMAC-SHA256
    // Note: This is a placeholder - actual implementation requires crypto library
    const stringToSign = `${accessSecret}${method}\n\n\n${timestamp}\n${url}`;
    // In real implementation, use: crypto.createHmac('sha256', accessSecret).update(stringToSign).digest('hex').toUpperCase()
    return "SIGNATURE_PLACEHOLDER";
}

async function tuyaRequest(method, endpoint, body, config) {
    const baseURL = getBaseURL(config.region);
    const timestamp = Date.now().toString();
    const url = `${baseURL}${endpoint}`;
    const sign = generateSign(method, endpoint, timestamp, config.accessSecret, body ? JSON.stringify(body) : "");
    
    const headers = {
        "client_id": config.accessId,
        "t": timestamp,
        "sign_method": "HMAC-SHA256",
        "sign": sign,
        "Content-Type": "application/json"
    };
    
    try {
        const response = await fetch(url, {
            method: method,
            headers: headers,
            body: body ? JSON.stringify(body) : undefined
        });
        
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        
        const data = await response.json();
        if (data.success === false) {
            console.error("Tuya API error:", data.msg);
            return null;
        }
        return data.result;
    } catch (e) {
        console.error(`Tuya API error (${method} ${endpoint}):`, e);
        return null;
    }
}

async function getDevices(config) {
    if (!config.accessId || !config.accessSecret) {
        return null;
    }
    
    return await tuyaRequest("GET", "/v1.0/devices", null, config);
}

async function getDeviceStatus(deviceId, config) {
    if (!config.accessId || !config.accessSecret) {
        return null;
    }
    
    return await tuyaRequest("GET", `/v1.0/devices/${deviceId}/status`, null, config);
}

async function controlDevice(deviceId, commands, config) {
    if (!config.accessId || !config.accessSecret) {
        return null;
    }
    
    return await tuyaRequest("POST", `/v1.0/devices/${deviceId}/commands`, { commands }, config);
}

// ============================================================================
// Main Widget Function
// ============================================================================

async function main() {
    const config = getConfig();
    const store = aio.storage.get("tuya") || {
        devices: [],
        mode: "full"
    };
    
    const mode = store.mode || "full";
    
    // Check if configured
    if (!config.accessId || !config.accessSecret) {
        return "❌ Not configured\n\nSet accessId and accessSecret\nLong press for options";
    }
    
    // Fetch devices
    const devicesData = await getDevices(config);
    
    if (!devicesData) {
        return "❌ Connection failed\n\nCheck credentials/region\nLong press for options";
    }
    
    const devices = devicesData.list || store.devices || [];
    
    // Fetch status for each device
    const deviceStatusPromises = devices.slice(0, 10).map(device => 
        getDeviceStatus(device.id, config).then(status => ({
            ...device,
            status: status || device.status || []
        }))
    );
    
    const devicesWithStatus = await Promise.all(deviceStatusPromises);
    
    // Update store
    store.devices = devicesWithStatus;
    aio.storage.set("tuya", store);
    
    // Generate output
    let o = "";
    
    if (mode === "compact") {
        const onlineDevices = devicesWithStatus.filter(d => d.online).length;
        const onDevices = devicesWithStatus.filter(d => {
            const switchStatus = (d.status || []).find(s => s.code === "switch_1" || s.code === "switch");
            return switchStatus && switchStatus.value;
        }).length;
        
        o += `📱 ${devicesWithStatus.length} Devices\n`;
        o += `🟢 ${onlineDevices} Online\n`;
        o += `💡 ${onDevices} On\n`;
        o += `\nTap: Refresh │ Long: Options`;
        return o;
    }
    
    // Full mode
    o += `📱 Tuya Devices (${devicesWithStatus.length})\n`;
    o += `━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    
    if (devicesWithStatus.length === 0) {
        o += "\nNo devices found\n";
        o += "Add device IDs in config\n";
        o += "Long press for options";
        return o;
    }
    
    for (const device of devicesWithStatus.slice(0, 8)) {
        const icon = getDeviceIcon(device);
        const status = getDeviceStatus(device);
        const name = (device.name || "Device").slice(0, 18).padEnd(18);
        o += `${icon} ${name} ${status.icon} ${status.text}\n`;
    }
    
    if (devicesWithStatus.length > 8) {
        o += `\n  +${devicesWithStatus.length - 8} more\n`;
    }
    
    o += `\n🔗 Tap: Refresh │ Long: Control`;
    
    return o;
}

// ============================================================================
// Event Handlers
// ============================================================================

aio.onTap = function() {
    aio.refresh();
};

aio.onLongTap = function() {
    const config = getConfig();
    const store = aio.storage.get("tuya") || {};
    const devices = store.devices || [];
    
    if (devices.length === 0) {
        aio.menu([
            "📊 Toggle Compact/Full Mode",
            "⚙️ Settings",
            "🔐 Configure Credentials",
            "❌ Cancel"
        ], async (index) => {
            switch(index) {
                case 0:
                    store.mode = store.mode === "compact" ? "full" : "compact";
                    aio.storage.set("tuya", store);
                    aio.refresh();
                    break;
                case 1:
                    showSettingsMenu(config);
                    break;
                case 2:
                    aio.toast("Set accessId and accessSecret in config");
                    break;
            }
        });
        return;
    }
    
    // Show device control menu
    const menuItems = devices.slice(0, 8).map(device => {
        const icon = getDeviceIcon(device);
        const status = getDeviceStatus(device);
        return `${icon} ${(device.name || "Device").slice(0, 20)} - ${status.text}`;
    });
    menuItems.push("📊 Toggle Mode");
    menuItems.push("⚙️ Settings");
    menuItems.push("❌ Cancel");
    
    aio.menu(menuItems, async (index) => {
        if (index < devices.length) {
            const device = devices[index];
            const switchStatus = (device.status || []).find(s => s.code === "switch_1" || s.code === "switch");
            const isOn = switchStatus && switchStatus.value;
            
            if (switchStatus) {
                const newValue = !isOn;
                const commands = [{
                    code: switchStatus.code,
                    value: newValue
                }];
                
                const result = await controlDevice(device.id, commands, config);
                if (result) {
                    aio.toast(`${device.name} turned ${newValue ? "on" : "off"}`);
                    aio.refresh();
                } else {
                    aio.toast("Failed to control device");
                }
            } else {
                aio.toast("Device doesn't support switch control");
            }
        } else if (index === devices.length) {
            store.mode = store.mode === "compact" ? "full" : "compact";
            aio.storage.set("tuya", store);
            aio.refresh();
        } else if (index === devices.length + 1) {
            showSettingsMenu(config);
        }
    });
};

function showSettingsMenu(config) {
    aio.menu([
        `🌍 Region: ${config.region}`,
        `📱 Devices: ${config.deviceIds.length}`,
        `🔑 Access ID: ${config.accessId ? "Set" : "Not set"}`,
        "❌ Cancel"
    ], (index) => {
        aio.toast("Edit settings in config");
    });
}

// ============================================================================
// Initialize
// ============================================================================

main();


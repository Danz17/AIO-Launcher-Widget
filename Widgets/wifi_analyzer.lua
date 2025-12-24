-- name = "WiFi Analyzer"
-- description = "WiFi network scanner and analyzer"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    scanInterval = 30,
    maxNetworksShow = 10,
    showHidden = false,
    sortBy = "signal", -- signal, name, security
    maxScansPerWindow = 4,
    scanWindowSeconds = 120
}

-- State
local state = {
    networks = {},
    scanHistory = {},
    lastScanTime = 0,
    signalHistory = {}
}

-- UTILITY FUNCTIONS

local function signalBar(dbm)
    local s = tonumber(dbm) or -100
    if s >= -50 then return "████" end
    if s >= -60 then return "███░" end
    if s >= -70 then return "██░░" end
    if s >= -80 then return "█░░░" end
    return "░░░░"
end

local function getSecurityType(capabilities)
    if not capabilities or capabilities == "" then return "Open", "" end
    local caps = capabilities:upper()
    local protocol = ""
    local encryption = ""

    if caps:find("WPA3") then
        protocol = "WPA3"
    elseif caps:find("WPA2") then
        protocol = "WPA2"
    elseif caps:find("WPA") then
        protocol = "WPA"
    elseif caps:find("WEP") then
        protocol = "WEP"
    else
        protocol = "Open"
    end

    if caps:find("AES") then
        encryption = "AES"
    elseif caps:find("TKIP") then
        encryption = "TKIP"
    elseif caps:find("CCMP") then
        encryption = "CCMP"
    end

    if encryption ~= "" then
        return protocol .. "/" .. encryption, encryption
    end
    return protocol, encryption
end

local function getFrequency(freq)
    if not freq then return "2.4GHz" end
    if freq >= 5000 then return "5GHz" end
    if freq >= 2400 then return "2.4GHz" end
    return "2.4GHz"
end

local function getChannel(freq)
    if not freq then return "?" end
    if freq >= 5000 then
        return tostring(math.floor((freq - 5000) / 5))
    end
    if freq >= 2400 then
        return tostring(math.floor((freq - 2400) / 5))
    end
    return "?"
end

local function recommendChannel(networks)
    local channelUsage = {}

    for _, net in ipairs(networks) do
        local ch = tonumber(getChannel(net.frequency))
        if ch and ch >= 1 and ch <= 14 then
            channelUsage[ch] = (channelUsage[ch] or 0) + 1
        end
    end

    local preferred = {1, 6, 11}
    local bestCh = nil
    local minUsage = math.huge

    for _, ch in ipairs(preferred) do
        local usage = channelUsage[ch] or 0
        if usage < minUsage then
            minUsage = usage
            bestCh = ch
        end
    end

    if minUsage > 3 then
        for ch = 1, 14 do
            local usage = channelUsage[ch] or 0
            if usage < minUsage then
                minUsage = usage
                bestCh = ch
            end
        end
    end

    return bestCh or 6
end

local function checkChannelConflicts(networks, channel)
    local conflicts = {}
    for _, net in ipairs(networks) do
        local netCh = tonumber(getChannel(net.frequency))
        if netCh and math.abs(netCh - channel) <= 4 then
            table.insert(conflicts, net)
        end
    end
    return conflicts
end

local function canScan()
    local now = os.time()
    local validScans = {}
    for _, scanTime in ipairs(state.scanHistory) do
        if now - scanTime < CONFIG.scanWindowSeconds then
            table.insert(validScans, scanTime)
        end
    end
    state.scanHistory = validScans

    if #state.scanHistory >= CONFIG.maxScansPerWindow then
        local oldestScan = state.scanHistory[1]
        local waitTime = CONFIG.scanWindowSeconds - (now - oldestScan)
        return false, waitTime
    end

    return true, 0
end

local function recordScan()
    table.insert(state.scanHistory, os.time())
    state.lastScanTime = os.time()
end

local function sortNetworks(networks, sortBy)
    local sorted = {}
    for _, net in ipairs(networks) do
        table.insert(sorted, net)
    end

    if sortBy == "signal" then
        table.sort(sorted, function(a, b)
            return (tonumber(a.rssi) or -100) > (tonumber(b.rssi) or -100)
        end)
    elseif sortBy == "name" then
        table.sort(sorted, function(a, b)
            return (a.ssid or "") < (b.ssid or "")
        end)
    elseif sortBy == "security" then
        table.sort(sorted, function(a, b)
            return getSecurityType(a.capabilities) < getSecurityType(b.capabilities)
        end)
    end

    return sorted
end

-- DISPLAY FUNCTION

local function showNetworks()
    local networks = state.networks

    -- Filter hidden networks if needed
    local filtered = {}
    for _, net in ipairs(networks) do
        if CONFIG.showHidden or (net.ssid and net.ssid ~= "") then
            table.insert(filtered, net)
        end
    end

    local sorted = sortNetworks(filtered, CONFIG.sortBy)
    local recommendedCh = recommendChannel(sorted)
    local channelConflicts = {}

    for _, net in ipairs(sorted) do
        local ch = tonumber(getChannel(net.frequency))
        if ch then
            local conflicts = checkChannelConflicts(sorted, ch)
            if #conflicts > 1 then
                channelConflicts[ch] = #conflicts
            end
        end
    end

    local o = "📶 WiFi Networks (" .. #sorted .. ")\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"

    if #sorted == 0 then
        o = o .. "\nNo networks found\n"
        o = o .. "Tap to scan for networks\n"
        o = o .. "Long press for options"
        ui:show_text(o)
        return
    end

    if recommendedCh and #sorted > 3 then
        o = o .. "\n💡 Best Channel: " .. recommendedCh .. "\n"
    end

    local maxShow = math.min(#sorted, CONFIG.maxNetworksShow)
    for i = 1, maxShow do
        local net = sorted[i]
        local ssid = (net.ssid or "[Hidden]"):sub(1, 18)
        local padding = string.rep(" ", 18 - #ssid)
        local sigBar = signalBar(net.rssi)
        local rssi = tostring(net.rssi or -100)
        local sec = getSecurityType(net.capabilities)
        local secPad = string.rep(" ", 8 - #sec)
        local ch = getChannel(net.frequency)
        local band = getFrequency(net.frequency)

        -- Update signal history
        if ssid ~= "[Hidden]" then
            if not state.signalHistory[ssid] then
                state.signalHistory[ssid] = {}
            end
            table.insert(state.signalHistory[ssid], net.rssi or -100)
            if #state.signalHistory[ssid] > 10 then
                table.remove(state.signalHistory[ssid], 1)
            end
        end

        -- Signal trend
        local trend = ""
        if state.signalHistory[ssid] and #state.signalHistory[ssid] >= 2 then
            local recent = state.signalHistory[ssid][#state.signalHistory[ssid]]
            local previous = state.signalHistory[ssid][#state.signalHistory[ssid] - 1]
            if recent > previous + 3 then
                trend = " ↗"
            elseif recent < previous - 3 then
                trend = " ↘"
            end
        end

        -- Conflict indicator
        local conflictIcon = ""
        if channelConflicts[tonumber(ch) or 0] and channelConflicts[tonumber(ch) or 0] > 1 then
            conflictIcon = " ⚠️"
        end

        o = o .. "  " .. ssid .. padding .. " " .. sigBar .. " " .. rssi .. "dBm" .. trend .. "\n"
        o = o .. "   " .. sec .. secPad .. " │ Ch" .. ch .. conflictIcon .. " │ " .. band .. "\n"
    end

    if #sorted > CONFIG.maxNetworksShow then
        o = o .. "\n  +" .. (#sorted - CONFIG.maxNetworksShow) .. " more\n"
    end

    o = o .. "\n🔗 Tap: Refresh │ Long: Options"
    ui:show_text(o)
end

-- MAIN ENTRY POINTS

function on_resume()
    local canDo, waitTime = canScan()
    if not canDo then
        ui:show_text("⏳ Scan throttled\n\nPlease wait " .. waitTime .. "s\n\nAndroid limits: 4 scans/2min\n\nTap to retry")
        return
    end

    ui:show_text("⏳ Scanning WiFi networks...")

    -- Request WiFi scan from Android API
    if android and android.getWifiList then
        local networks = android.getWifiList()
        if networks and #networks > 0 then
            recordScan()
            state.networks = networks
            showNetworks()
        else
            ui:show_text("📶 No networks found\n\nTap to scan for networks\nLong press for options")
        end
    else
        ui:show_text("📶 WiFi Analyzer\n\n❌ WiFi API not available\n\nThis widget requires Android WiFi access")
    end
end

function on_click()
    on_resume()
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Force Scan Now",
        "🔀 Sort: " .. CONFIG.sortBy,
        "👁️ Hidden: " .. (CONFIG.showHidden and "Yes" or "No"),
        "📋 Max: " .. CONFIG.maxNetworksShow,
        "❌ Close"
    })
end

function on_context_menu_click(idx)
    if idx == 0 then
        on_resume()
    elseif idx == 1 then
        local sorts = {"signal", "name", "security"}
        local currentIdx = 1
        for i, v in ipairs(sorts) do
            if v == CONFIG.sortBy then
                currentIdx = i
                break
            end
        end
        local nextIdx = (currentIdx % #sorts) + 1
        CONFIG.sortBy = sorts[nextIdx]
        ui:show_toast("Sort by: " .. CONFIG.sortBy)
        showNetworks()
    elseif idx == 2 then
        CONFIG.showHidden = not CONFIG.showHidden
        ui:show_toast("Show hidden: " .. (CONFIG.showHidden and "Yes" or "No"))
        showNetworks()
    elseif idx == 3 then
        ui:show_toast("Edit maxNetworksShow in config")
    end
end

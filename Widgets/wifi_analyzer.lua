-- name = "WiFi Analyzer"
-- description = "WiFi network scanner and analyzer"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    scanInterval = 30,
    maxNetworksShow = 10,
    showHidden = false,
    sortBy = "signal" -- signal, name, security
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

local function signalIcon(dbm)
    local s = tonumber(dbm) or -100
    if s >= -65 then return "📶" end
    if s >= -75 then return "📶" end
    if s >= -85 then return "📉" end
    return "⚠️"
end

local function getSecurityType(capabilities)
    if not capabilities or capabilities == "" then return "Open" end
    local caps = capabilities:upper()
    if caps:find("WPA3") then return "WPA3" end
    if caps:find("WPA2") then return "WPA2" end
    if caps:find("WPA") then return "WPA" end
    if caps:find("WEP") then return "WEP" end
    return "Open"
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

-- MAIN FUNCTION

function on_resume()
    ui:show_text("⏳ Scanning WiFi networks...")
    
    -- Request WiFi scan from Android API
    if android and android.getWifiList then
        local networks = android.getWifiList()
        if networks and #networks > 0 then
            showNetworks(networks)
        else
            ui:show_text("📶 No networks found\n\nTap to scan for networks\nLong press for options")
        end
    else
        -- Fallback: Show message
        ui:show_text("📶 WiFi Analyzer\n\n❌ WiFi API not available\n\nThis widget requires Android WiFi access")
    end
end

function showNetworks(networks)
    -- Filter hidden networks if needed
    local filtered = {}
    for _, net in ipairs(networks) do
        if CONFIG.showHidden or (net.ssid and net.ssid ~= "") then
            table.insert(filtered, net)
        end
    end
    
    -- Sort networks
    local sorted = sortNetworks(filtered, CONFIG.sortBy)
    
    -- Generate output
    local o = "📶 WiFi Networks (" .. #sorted .. ")\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if #sorted == 0 then
        o = o .. "\nNo networks found\n"
        o = o .. "Tap to scan for networks\n"
        o = o .. "Long press for options"
        ui:show_text(o)
        return
    end
    
    local maxShow = math.min(#sorted, CONFIG.maxNetworksShow)
    for i = 1, maxShow do
        local net = sorted[i]
        local ssid = (net.ssid or "[Hidden]"):sub(1, 18)
        local padding = string.rep(" ", 18 - #ssid)
        local sigBar = signalBar(net.rssi)
        local rssi = tostring(net.rssi or -100)
        local sec = getSecurityType(net.capabilities)
        local secPad = string.rep(" ", 5 - #sec)
        local ch = getChannel(net.frequency)
        local band = getFrequency(net.frequency)
        
        o = o .. "  " .. ssid .. padding .. " " .. sigBar .. " " .. rssi .. "dBm\n"
        o = o .. "   " .. sec .. secPad .. " │ Ch" .. ch .. " │ " .. band .. "\n"
    end
    
    if #sorted > CONFIG.maxNetworksShow then
        o = o .. "\n  +" .. (#sorted - CONFIG.maxNetworksShow) .. " more\n"
    end
    
    o = o .. "\n🔗 Tap: Refresh │ Long: Options"
    
    ui:show_text(o)
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
    }, function(index)
        if index == 0 then
            on_resume()
        elseif index == 1 then
            local sorts = {"signal", "name", "security"}
            local currentIdx = 1
            for i, v in ipairs(sorts) do
                if v == CONFIG.sortBy then currentIdx = i break end
            end
            local nextIdx = (currentIdx % #sorts) + 1
            CONFIG.sortBy = sorts[nextIdx]
            system:toast("Sort by: " .. CONFIG.sortBy)
            on_resume()
        elseif index == 2 then
            CONFIG.showHidden = not CONFIG.showHidden
            system:toast("Show hidden: " .. (CONFIG.showHidden and "Yes" or "No"))
            on_resume()
        end
    end)
end


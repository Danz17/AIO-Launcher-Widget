-- name = "Enpass"
-- description = "Enpass password manager status"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    serverUrl = "",  -- Leave empty for local vault
    apiKey = "",
    vaultPath = ""  -- Local vault path
}

-- UTILITY FUNCTIONS

local function fmtDate(timestamp)
    if not timestamp then return "Never" end
    
    local now = os.time()
    local diff = now - timestamp
    local diffMins = math.floor(diff / 60)
    local diffHours = math.floor(diff / 3600)
    local diffDays = math.floor(diff / 86400)
    
    if diffMins < 1 then return "Just now" end
    if diffMins < 60 then return diffMins .. "m ago" end
    if diffHours < 24 then return diffHours .. "h ago" end
    if diffDays < 7 then return diffDays .. "d ago" end
    
    return os.date("%Y-%m-%d", timestamp)
end

local function progressBar(percent, width)
    width = width or 10
    local filled = math.floor((percent / 100) * width)
    return string.rep("█", filled) .. string.rep("░", width - filled)
end

-- ENPASS API FUNCTIONS

local function checkLocalVault(callback)
    -- Try to check local vault status
    -- This would require platform-specific APIs
    -- For now, return a mock structure
    callback({
        locked = true,
        itemCount = 0,
        lastSync = nil,
        syncStatus = "unknown",
        syncProvider = "Local"
    })
end

local function enpassRequest(endpoint, callback)
    if not CONFIG.serverUrl or CONFIG.serverUrl == "" then
        checkLocalVault(callback)
        return
    end
    
    local url = CONFIG.serverUrl .. endpoint
    local headers = {
        ["Content-Type"] = "application/json"
    }
    
    if CONFIG.apiKey and CONFIG.apiKey ~= "" then
        headers["Authorization"] = "Bearer " .. CONFIG.apiKey
    end
    
    http:get(url, function(data, code)
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res then
                callback(res)
                return
            end
        end
        callback(nil)
    end, headers)
end

local function getVaultStatus(callback)
    if CONFIG.serverUrl and CONFIG.serverUrl ~= "" then
        enpassRequest("/api/v1/status", callback)
    else
        checkLocalVault(callback)
    end
end

-- MAIN FUNCTION

function on_resume()
    ui:show_text("⏳ Checking vault status...")
    
    getVaultStatus(function(status)
        if not status then
            ui:show_text("❌ Cannot access vault\n\nCheck configuration\n\nFor local vault, Enpass API\nmay not be available\n\nLong press for help")
            return
        end
        
        showStatus(status)
    end)
end

function showStatus(status)
    local isLocked = status.locked ~= false
    local itemCount = status.itemCount or 0
    local lastSync = status.lastSync
    local syncStatus = status.syncStatus or "unknown"
    local syncProvider = status.syncProvider or "Local"
    local weakPasswords = status.weakPasswords or 0
    local duplicatePasswords = status.duplicatePasswords or 0
    
    -- Calculate security score
    local securityScore = 100
    if weakPasswords > 0 then
        securityScore = securityScore - math.min(30, weakPasswords * 2)
    end
    if duplicatePasswords > 0 then
        securityScore = securityScore - math.min(20, duplicatePasswords * 2)
    end
    if syncStatus == "error" then
        securityScore = securityScore - 10
    end
    securityScore = math.max(0, securityScore)
    
    local lockIcon = isLocked and "🔒" or "🔓"
    local lockStatus = isLocked and "Locked" or "Unlocked"
    
    local o = lockIcon .. " Enpass Vault - " .. lockStatus .. "\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    o = o .. "\n📦 VAULT INFO\n"
    o = o .. "Items: " .. itemCount .. "\n"
    o = o .. "Status: " .. lockStatus .. "\n"
    
    o = o .. "\n🔄 SYNC STATUS\n"
    local syncIcon = "❌"
    if syncStatus == "synced" then
        syncIcon = "✅"
    elseif syncStatus == "syncing" then
        syncIcon = "⟳"
    end
    
    o = o .. syncIcon .. " " .. syncStatus:gsub("^%l", string.upper) .. "\n"
    o = o .. "Provider: " .. syncProvider .. "\n"
    o = o .. "Last Sync: " .. fmtDate(lastSync) .. "\n"
    
    o = o .. "\n🔐 SECURITY\n"
    o = o .. "Score " .. progressBar(securityScore, 10) .. " " .. securityScore .. "%\n"
    
    if weakPasswords > 0 then
        o = o .. "⚠️ Weak: " .. weakPasswords .. "\n"
    end
    if duplicatePasswords > 0 then
        o = o .. "⚠️ Duplicate: " .. duplicatePasswords .. "\n"
    end
    if weakPasswords == 0 and duplicatePasswords == 0 then
        o = o .. "✅ All passwords secure\n"
    end
    
    o = o .. "\n🔗 Tap: Open Enpass │ Long: Refresh"
    
    ui:show_text(o)
end

function on_click()
    system:toast("Opening Enpass...")
    -- Try to open Enpass app
    -- system:open_app("com.sinex.enpass")
end

function on_long_click()
    on_resume()
end


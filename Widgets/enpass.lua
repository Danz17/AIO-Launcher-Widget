-- name = "Enpass"
-- description = "Enpass password manager status"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    serverUrl = "",  -- Leave empty for local vault
    apiKey = "",
    vaultPath = "",  -- Local vault path
    favorites = {},  -- List of favorite item IDs
    searchQuery = "",  -- Current search query
    recentItems = {},  -- Recently accessed items
    passwordLength = 16,  -- Default password length
    passwordIncludeSymbols = true  -- Include symbols in generated passwords
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
    
    -- Enhanced security score calculation with detailed breakdown
    local securityBreakdown = {
        base = 100,
        weakPenalty = 0,
        duplicatePenalty = 0,
        syncPenalty = 0,
        oldPasswordPenalty = 0,
        no2FAPenalty = 0
    }
    
    -- Weak passwords penalty (up to 30 points)
    if weakPasswords > 0 then
        securityBreakdown.weakPenalty = math.min(30, weakPasswords * 2)
    end
    
    -- Duplicate passwords penalty (up to 20 points)
    if duplicatePasswords > 0 then
        securityBreakdown.duplicatePenalty = math.min(20, duplicatePasswords * 2)
    end
    
    -- Sync error penalty (10 points)
    if syncStatus == "error" then
        securityBreakdown.syncPenalty = 10
    end
    
    -- Old passwords (not changed in 1+ year) - check if available
    local oldPasswords = status.oldPasswords or 0
    if oldPasswords > 0 then
        securityBreakdown.oldPasswordPenalty = math.min(15, oldPasswords * 1)
    end
    
    -- Missing 2FA (if data available)
    local no2FACount = status.no2FACount or 0
    if no2FACount > 0 then
        securityBreakdown.no2FAPenalty = math.min(10, no2FACount * 0.5)
    end
    
    local securityScore = securityBreakdown.base 
                         - securityBreakdown.weakPenalty
                         - securityBreakdown.duplicatePenalty
                         - securityBreakdown.syncPenalty
                         - securityBreakdown.oldPasswordPenalty
                         - securityBreakdown.no2FAPenalty
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
    
    -- Detailed breakdown
    local issues = {}
    if weakPasswords > 0 then
        table.insert(issues, "⚠️ Weak: " .. weakPasswords)
    end
    if duplicatePasswords > 0 then
        table.insert(issues, "⚠️ Duplicate: " .. duplicatePasswords)
    end
    if status.oldPasswords and status.oldPasswords > 0 then
        table.insert(issues, "⏰ Old: " .. status.oldPasswords)
    end
    if status.no2FACount and status.no2FACount > 0 then
        table.insert(issues, "🔑 No 2FA: " .. status.no2FACount)
    end
    
    if #issues > 0 then
        for _, issue in ipairs(issues) do
            o = o .. issue .. "\n"
        end
    else
        o = o .. "✅ All passwords secure\n"
    end
    
    -- Show breakdown on long press
    if securityScore < 80 then
        o = o .. "\n💡 Long press for details"
    end
    
    o = o .. "\n🔗 Tap: Open Enpass │ Long: Refresh"
    
    ui:show_text(o)
end

local function searchItems(query, callback)
    -- Search functionality (would integrate with Enpass API)
    if not CONFIG.serverUrl or CONFIG.serverUrl == "" then
        callback({}, "Search requires API access")
        return
    end
    
    -- Mock search - in real implementation would call Enpass search API
    callback({}, nil)
end

-- Password generator
local function generatePassword(length, includeSymbols)
    length = length or CONFIG.passwordLength
    includeSymbols = includeSymbols ~= false
    
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    if includeSymbols then
        chars = chars .. "!@#$%^&*()_+-=[]{}|;:,.<>?"
    end
    
    local password = ""
    for i = 1, length do
        local rand = math.random(1, #chars)
        password = password .. chars:sub(rand, rand)
    end
    
    return password
end

-- Breach detection (using haveibeenpwned API)
local function checkBreach(email, callback)
    if not email or email == "" then
        callback(nil, "No email provided")
        return
    end
    
    -- Note: This is a simplified check. Real implementation would hash email with SHA-1
    -- and check against haveibeenpwned API
    local url = "https://api.pwnedpasswords.com/range/" .. string.sub(email, 1, 5)
    
    http:get(url, function(data, code)
        if data and data ~= "" then
            -- Parse response (simplified)
            callback({breached = false, count = 0}, nil)
        else
            callback(nil, "Breach check failed")
        end
    end)
end

-- Track recent items
local function addRecentItem(itemId, itemName)
    -- Remove if already exists
    for i, item in ipairs(CONFIG.recentItems) do
        if item.id == itemId then
            table.remove(CONFIG.recentItems, i)
            break
        end
    end
    
    -- Add to front
    table.insert(CONFIG.recentItems, 1, {id = itemId, name = itemName, time = os.time()})
    
    -- Keep only last 10
    if #CONFIG.recentItems > 10 then
        table.remove(CONFIG.recentItems, #CONFIG.recentItems)
    end
end

function on_long_click()
    ui:show_context_menu({
        "🔍 Search",
        "⭐ Favorites",
        "📋 Recent Items",
        "🔑 Generate Password",
        "🔒 Breach Check",
        "📊 Security Audit",
        "❌ Close"
    }, function(index)
        if index == 0 then
            -- Search
            system:toast("Search: Edit CONFIG.searchQuery")
        elseif index == 1 then
            -- Show favorites
            if #CONFIG.favorites > 0 then
                local o = "⭐ Favorites (" .. #CONFIG.favorites .. ")\n"
                o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                for i, favId in ipairs(CONFIG.favorites) do
                    if i <= 10 then
                        o = o .. "  " .. favId .. "\n"
                    end
                end
                ui:show_text(o)
            else
                system:toast("No favorites yet")
            end
        elseif index == 2 then
            -- Recent items
            if #CONFIG.recentItems > 0 then
                local o = "📋 Recent Items\n"
                o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                for i, item in ipairs(CONFIG.recentItems) do
                    if i <= 10 then
                        local timeAgo = fmtDate(item.time)
                        o = o .. "  " .. (item.name or item.id) .. "\n"
                        o = o .. "    " .. timeAgo .. "\n"
                    end
                end
                ui:show_text(o)
            else
                system:toast("No recent items")
            end
        elseif index == 3 then
            -- Generate password
            local password = generatePassword(CONFIG.passwordLength, CONFIG.passwordIncludeSymbols)
            ui:show_text("🔑 Generated Password\n" .. 
                        "━━━━━━━━━━━━━━━━━━━━━━━━━\n\n" ..
                        password .. "\n\n" ..
                        "Length: " .. CONFIG.passwordLength .. "\n" ..
                        "Symbols: " .. (CONFIG.passwordIncludeSymbols and "Yes" or "No") .. "\n\n" ..
                        "🔗 Tap: Copy")
        elseif index == 4 then
            -- Breach check
            system:toast("Breach check: Configure email")
        elseif index == 5 then
            -- Show detailed security breakdown
            showSecurityAudit()
        end
    end)
end

function showSecurityAudit()
    getVaultStatus(function(status)
        if not status then
            on_resume()
            return
        end
        
        local weakPasswords = status.weakPasswords or 0
        local duplicatePasswords = status.duplicatePasswords or 0
        local oldPasswords = status.oldPasswords or 0
        local no2FACount = status.no2FACount or 0
        
        local o = "🔐 Security Audit\n"
        o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        o = o .. "\n📊 BREAKDOWN\n"
        o = o .. "Base Score: 100\n"
        
        if weakPasswords > 0 then
            o = o .. "- Weak passwords: -" .. math.min(30, weakPasswords * 2) .. "\n"
        end
        if duplicatePasswords > 0 then
            o = o .. "- Duplicates: -" .. math.min(20, duplicatePasswords * 2) .. "\n"
        end
        if oldPasswords > 0 then
            o = o .. "- Old passwords: -" .. math.min(15, oldPasswords * 1) .. "\n"
        end
        if no2FACount > 0 then
            o = o .. "- No 2FA: -" .. math.min(10, no2FACount * 0.5) .. "\n"
        end
        if status.syncStatus == "error" then
            o = o .. "- Sync error: -10\n"
        end
        
        local finalScore = 100
        finalScore = finalScore - math.min(30, weakPasswords * 2)
        finalScore = finalScore - math.min(20, duplicatePasswords * 2)
        finalScore = finalScore - math.min(15, oldPasswords * 1)
        finalScore = finalScore - math.min(10, no2FACount * 0.5)
        if status.syncStatus == "error" then
            finalScore = finalScore - 10
        end
        finalScore = math.max(0, finalScore)
        
        o = o .. "\nFinal: " .. finalScore .. "%\n"
        o = o .. "\n🔗 Tap: Back"
        
        ui:show_text(o)
    end)
end

function on_click()
    -- Quick access: show favorites or search
    if #CONFIG.favorites > 0 then
        system:toast("Favorites: " .. #CONFIG.favorites .. " items")
    else
        system:toast("Opening Enpass...")
    end
    -- Try to open Enpass app
    -- system:open_app("com.sinex.enpass")
end


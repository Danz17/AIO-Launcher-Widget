-- name = "Enpass"
-- description = "Enpass password manager status"
-- foldable = "true"

-- CONFIGURATION
local CONFIG = {
    serverUrl = "",  -- Leave empty for local vault
    apiKey = "",
    vaultPath = "",
    favorites = {},
    recentItems = {},
    passwordLength = 16,
    passwordIncludeSymbols = true
}

-- State
local state = {
    status = nil,
    error = nil
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

-- DISPLAY FUNCTIONS

local function showStatus()
    if state.error then
        ui:show_text("❌ Cannot access vault\n\n" .. state.error .. "\n\nFor local vault, Enpass API\nmay not be available\n\nLong press for help")
        return
    end

    local status = state.status or {}
    local isLocked = status.locked ~= false
    local itemCount = status.itemCount or 0
    local lastSync = status.lastSync
    local syncStatus = status.syncStatus or "unknown"
    local syncProvider = status.syncProvider or "Local"
    local weakPasswords = status.weakPasswords or 0
    local duplicatePasswords = status.duplicatePasswords or 0
    local oldPasswords = status.oldPasswords or 0
    local no2FACount = status.no2FACount or 0

    -- Security score calculation
    local securityScore = 100
    securityScore = securityScore - math.min(30, weakPasswords * 2)
    securityScore = securityScore - math.min(20, duplicatePasswords * 2)
    securityScore = securityScore - math.min(15, oldPasswords * 1)
    securityScore = securityScore - math.min(10, no2FACount * 0.5)
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

    -- Issues
    local issues = {}
    if weakPasswords > 0 then
        table.insert(issues, "⚠️ Weak: " .. weakPasswords)
    end
    if duplicatePasswords > 0 then
        table.insert(issues, "⚠️ Duplicate: " .. duplicatePasswords)
    end
    if oldPasswords > 0 then
        table.insert(issues, "⏰ Old: " .. oldPasswords)
    end
    if no2FACount > 0 then
        table.insert(issues, "🔑 No 2FA: " .. no2FACount)
    end

    if #issues > 0 then
        for _, issue in ipairs(issues) do
            o = o .. issue .. "\n"
        end
    else
        o = o .. "✅ All passwords secure\n"
    end

    if securityScore < 80 then
        o = o .. "\n💡 Long press for details"
    end

    o = o .. "\n🔗 Tap: Open Enpass │ Long: Options"
    ui:show_text(o)
end

-- NETWORK CALLBACKS

function on_network_result_status(body, code)
    if code ~= 200 or not body or body == "" then
        state.error = "HTTP " .. tostring(code)
        showStatus()
        return
    end

    local ok, data = pcall(function() return json:decode(body) end)
    if not ok or not data then
        state.error = "Invalid response"
        showStatus()
        return
    end

    state.error = nil
    state.status = data
    showStatus()
end

function on_network_error_status(err)
    state.error = err or "Network error"
    showStatus()
end

-- MAIN ENTRY POINTS

function on_resume()
    ui:show_text("⏳ Checking vault status...")

    if not CONFIG.serverUrl or CONFIG.serverUrl == "" then
        -- Local vault - show mock status
        state.status = {
            locked = true,
            itemCount = 0,
            lastSync = nil,
            syncStatus = "unknown",
            syncProvider = "Local"
        }
        showStatus()
        return
    end

    local url = CONFIG.serverUrl .. "/api/v1/status"
    http:get(url, "status")
end

function on_click()
    if #CONFIG.favorites > 0 then
        ui:show_toast("Favorites: " .. #CONFIG.favorites .. " items")
    else
        ui:show_toast("Opening Enpass...")
    end
end

function on_long_click()
    local alertCount = 0
    for _ in pairs(CONFIG.favorites) do
        alertCount = alertCount + 1
    end

    ui:show_context_menu({
        "🔍 Search",
        "⭐ Favorites",
        "📋 Recent Items",
        "🔑 Generate Password",
        "🔒 Breach Check",
        "📊 Security Audit",
        "❌ Close"
    })
end

function on_context_menu_click(idx)
    if idx == 0 then
        ui:show_toast("Search: Edit CONFIG.searchQuery")
    elseif idx == 1 then
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
            ui:show_toast("No favorites yet")
        end
    elseif idx == 2 then
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
            ui:show_toast("No recent items")
        end
    elseif idx == 3 then
        local password = generatePassword(CONFIG.passwordLength, CONFIG.passwordIncludeSymbols)
        ui:show_text("🔑 Generated Password\n" ..
                    "━━━━━━━━━━━━━━━━━━━━━━━━━\n\n" ..
                    password .. "\n\n" ..
                    "Length: " .. CONFIG.passwordLength .. "\n" ..
                    "Symbols: " .. (CONFIG.passwordIncludeSymbols and "Yes" or "No") .. "\n\n" ..
                    "🔗 Tap: Copy")
    elseif idx == 4 then
        ui:show_toast("Breach check: Configure email")
    elseif idx == 5 then
        -- Security audit
        local status = state.status or {}
        local weakPasswords = status.weakPasswords or 0
        local duplicatePasswords = status.duplicatePasswords or 0
        local oldPasswords = status.oldPasswords or 0
        local no2FACount = status.no2FACount or 0

        local finalScore = 100
        finalScore = finalScore - math.min(30, weakPasswords * 2)
        finalScore = finalScore - math.min(20, duplicatePasswords * 2)
        finalScore = finalScore - math.min(15, oldPasswords * 1)
        finalScore = finalScore - math.min(10, no2FACount * 0.5)
        if status.syncStatus == "error" then
            finalScore = finalScore - 10
        end
        finalScore = math.max(0, finalScore)

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

        o = o .. "\nFinal: " .. finalScore .. "%\n"
        o = o .. "\n🔗 Tap: Back"

        ui:show_text(o)
    end
end

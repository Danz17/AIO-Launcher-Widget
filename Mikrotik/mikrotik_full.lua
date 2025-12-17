-- name = "MikroTik Monitor"
-- description = "Comprehensive router monitoring with LTE, WiFi, clients, data usage"
-- author = "Alaa"
-- foldable = "true"
-- type = "widget"

-- ============================================================================
-- CONFIGURATION - EDIT THESE VALUES
-- ============================================================================
local CONFIG = {
    ip = "10.1.1.1",
    -- Base64 of "admin:admin123" - regenerate if you change credentials
    -- Use: echo -n "user:pass" | base64
    auth = "Basic YWRtaW46YWRtaW4xMjM=",
    
    -- Data limits
    daily_limit_gb = 10,
    monthly_limit_gb = 100,
    
    -- Display
    max_clients = 6,
    graph_width = 18,
    
    -- Interface names (adjust to match your router)
    lte_interface = "lte1",
    hotspot_interface = "wifi2-hotspot"
}

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
    mode = "full",  -- "full" or "compact"
    
    -- Speed tracking
    prev_lte_rx = 0,
    prev_lte_tx = 0,
    prev_time = 0,
    
    -- History for graphs
    hist_down = {},
    hist_up = {},
    hist_signal = {},
    hist_cpu = {},
    
    -- Data usage
    today_bytes = 0,
    month_bytes = 0,
    last_day = 0,
    last_month = 0,
    
    -- Cached data
    resource = nil,
    interfaces = nil,
    lte_info = nil,
    hotspot_clients = nil,
    dhcp_leases = nil
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function fmt_speed(bps)
    if not bps or bps < 0 then return "0" end
    if bps >= 1e9 then return string.format("%.1fG", bps / 1e9) end
    if bps >= 1e6 then return string.format("%.1fM", bps / 1e6) end
    if bps >= 1e3 then return string.format("%.0fK", bps / 1e3) end
    return string.format("%.0f", bps)
end

local function fmt_bytes(bytes)
    if not bytes or bytes < 0 then return "0B" end
    if bytes >= 1e12 then return string.format("%.2fTB", bytes / 1e12) end
    if bytes >= 1e9 then return string.format("%.2fGB", bytes / 1e9) end
    if bytes >= 1e6 then return string.format("%.1fMB", bytes / 1e6) end
    if bytes >= 1e3 then return string.format("%.0fKB", bytes / 1e3) end
    return string.format("%dB", math.floor(bytes))
end

local function fmt_uptime(str)
    if not str then return "?" end
    -- Extract first two units: "1d20h2m31s" -> "1d20h"
    local parts = {}
    for num, unit in string.gmatch(str, "(%d+)([wdhms])") do
        table.insert(parts, num .. unit)
        if #parts >= 2 then break end
    end
    return table.concat(parts, "")
end

local function progress_bar(percent, width)
    width = width or 10
    percent = math.max(0, math.min(100, percent or 0))
    local filled = math.floor((percent / 100) * width + 0.5)
    return string.rep("█", filled) .. string.rep("░", width - filled)
end

local function mini_graph(history, width)
    width = width or 15
    local bars = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
    
    if not history or #history == 0 then
        return string.rep(bars[1], width)
    end
    
    -- Find max value
    local max_val = 1
    for i = 1, #history do
        if history[i] and history[i] > max_val then
            max_val = history[i]
        end
    end
    
    -- Build graph from recent values
    local result = ""
    local start_idx = math.max(1, #history - width + 1)
    for i = start_idx, #history do
        local v = history[i] or 0
        local idx = math.min(8, math.floor((v / max_val) * 7) + 1)
        result = result .. bars[idx]
    end
    
    -- Pad if needed
    local pad = width - (#history - start_idx + 1)
    if pad > 0 then
        result = string.rep(bars[1], pad) .. result
    end
    
    return result
end

local function signal_bars(dbm)
    local s = tonumber(dbm) or -100
    if s >= -65 then return "█████" end
    if s >= -75 then return "████░" end
    if s >= -85 then return "███░░" end
    if s >= -95 then return "██░░░" end
    return "█░░░░"
end

local function signal_icon(dbm)
    local s = tonumber(dbm) or -100
    if s >= -65 then return "📶" end
    if s >= -75 then return "📶" end
    if s >= -85 then return "📉" end
    return "⚠️"
end

local function safe_get(tbl, key, default)
    if tbl and type(tbl) == "table" then
        return tbl[key] or default
    end
    return default
end

local function add_history(tbl, value, max_len)
    max_len = max_len or 30
    table.insert(tbl, value)
    while #tbl > max_len do
        table.remove(tbl, 1)
    end
end

-- ============================================================================
-- API FUNCTIONS  
-- ============================================================================

local pending = 0
local last_error = ""

local function api_get(endpoint, callback)
    local url = "http://" .. CONFIG.ip .. "/rest" .. endpoint
    
    http:get(url, "", function(data, code)
        -- Log response details
        if not data or data == "" then
            last_error = "Empty response from " .. endpoint .. " (HTTP " .. tostring(code) .. ")"
            callback(nil)
            return
        end
        
        -- Check for HTML (login page)
        if string.find(data, "<html") or string.find(data, "<HTML") then
            last_error = "Got HTML instead of JSON - Auth failed for " .. endpoint
            callback(nil)
            return
        end
        
        -- Try to decode JSON
        local ok, result = pcall(function() return json:decode(data) end)
        if ok and result then
            last_error = ""  -- Clear error on success
            callback(result)
            return
        else
            last_error = "JSON decode failed for " .. endpoint .. ": " .. tostring(result)
            callback(nil)
        end
    end, {Authorization = CONFIG.auth})
end

local function api_post(endpoint, body, callback)
    local url = "http://" .. CONFIG.ip .. "/rest" .. endpoint
    local json_body = json:encode(body)
    
    http:post(url, json_body, function(data, code)
        callback(code == 200)
    end, {
        Authorization = CONFIG.auth,
        ["Content-Type"] = "application/json"
    })
end

-- ============================================================================
-- DATA COLLECTION
-- ============================================================================

local function collect_data(on_complete)
    pending = 5
    
    local function check_done()
        pending = pending - 1
        if pending <= 0 then
            on_complete()
        end
    end
    
    -- System resource
    api_get("/system/resource", function(data)
        state.resource = data
        check_done()
    end)
    
    -- Interfaces
    api_get("/interface", function(data)
        state.interfaces = data
        check_done()
    end)
    
    -- LTE info
    api_get("/interface/lte/info", function(data)
        if data and type(data) == "table" and data[1] then
            state.lte_info = data[1]
        else
            state.lte_info = nil
        end
        check_done()
    end)
    
    -- Hotspot clients
    api_get("/ip/hotspot/active", function(data)
        state.hotspot_clients = data
        check_done()
    end)
    
    -- DHCP leases
    api_get("/ip/dhcp-server/lease", function(data)
        state.dhcp_leases = data
        check_done()
    end)
end

-- ============================================================================
-- DATA PROCESSING
-- ============================================================================

local function find_interface(name_pattern)
    if not state.interfaces or type(state.interfaces) ~= "table" then
        return nil
    end
    
    for i = 1, #state.interfaces do
        local iface = state.interfaces[i]
        if iface and type(iface) == "table" then
            local name = iface["name"] or ""
            if string.find(name, name_pattern, 1, true) then
                return iface
            end
        end
    end
    return nil
end

local function calculate_speeds()
    local now = os.time()
    local dt = now - state.prev_time
    if dt <= 0 or dt > 120 then dt = 30 end
    state.prev_time = now
    
    local down_speed, up_speed = 0, 0
    
    local lte = find_interface("lte")
    if lte then
        local rx = tonumber(lte["rx-byte"]) or 0
        local tx = tonumber(lte["tx-byte"]) or 0
        
        if state.prev_lte_rx > 0 and rx >= state.prev_lte_rx then
            down_speed = (rx - state.prev_lte_rx) / dt
            up_speed = (tx - state.prev_lte_tx) / dt
        end
        
        state.prev_lte_rx = rx
        state.prev_lte_tx = tx
    end
    
    -- Update data usage
    local today = os.date("%j")  -- Day of year
    local month = os.date("%m")
    
    if state.last_day ~= today then
        state.today_bytes = 0
        state.last_day = today
    end
    if state.last_month ~= month then
        state.month_bytes = 0
        state.last_month = month
    end
    
    if down_speed > 0 or up_speed > 0 then
        local added = (down_speed + up_speed) * dt
        state.today_bytes = state.today_bytes + added
        state.month_bytes = state.month_bytes + added
    end
    
    return down_speed, up_speed
end

-- ============================================================================
-- DISPLAY GENERATION
-- ============================================================================

local function generate_display()
    local res = state.resource
    
    if not res then
        local err_msg = "⚠️ Cannot connect to router\n\n" ..
               "IP: " .. CONFIG.ip .. "\n"
        
        if last_error ~= "" then
            err_msg = err_msg .. "\n🔴 Error:\n" .. last_error .. "\n"
        end
        
        err_msg = err_msg .. "\nCheck:\n" ..
               "• Router is reachable\n" ..
               "• REST API enabled\n" ..
               "• Credentials correct\n" ..
               "• Auth format: Basic base64(user:pass)\n\n" ..
               "Tap to open WebFig"
        
        return err_msg
    end
    
    -- Parse system info
    local cpu = tonumber(res["cpu-load"]) or 0
    local mem_free = tonumber(res["free-memory"]) or 0
    local mem_total = tonumber(res["total-memory"]) or 1
    local mem = math.floor((1 - mem_free / mem_total) * 100)
    local uptime = res["uptime"] or "?"
    local board = res["board-name"] or "MikroTik"
    local version = res["version"] or ""
    
    -- Get LTE interface and info
    local lte = find_interface("lte")
    local lte_running = lte and lte["running"] == "true"
    
    local signal = -100
    local operator = ""
    local tech = ""
    if state.lte_info and type(state.lte_info) == "table" then
        signal = tonumber(state.lte_info["rssi"]) or tonumber(state.lte_info["rsrp"]) or -100
        operator = state.lte_info["operator"] or ""
        tech = state.lte_info["access-technology"] or ""
    end
    
    -- Calculate speeds
    local down_speed, up_speed = calculate_speeds()
    
    -- Update history
    add_history(state.hist_down, down_speed * 8)
    add_history(state.hist_up, up_speed * 8)
    add_history(state.hist_signal, signal)
    add_history(state.hist_cpu, cpu)
    
    -- Count clients
    local client_count = 0
    if state.hotspot_clients and type(state.hotspot_clients) == "table" then
        client_count = #state.hotspot_clients
    end
    
    -- Active WAN
    local active_wan = lte_running and "LTE" or "—"
    
    local o = ""
    
    -- ===================== COMPACT MODE =====================
    if state.mode == "compact" then
        o = "📡 " .. active_wan
        o = o .. " ↓" .. fmt_speed(down_speed * 8)
        o = o .. " ↑" .. fmt_speed(up_speed * 8)
        
        if lte_running then
            o = o .. " │ " .. signal .. "dBm"
        end
        
        o = o .. "\n👥 " .. client_count
        o = o .. " │ 📊 " .. fmt_bytes(state.today_bytes)
        o = o .. " │ CPU " .. cpu .. "%"
        
        o = o .. "\n" .. mini_graph(state.hist_down, 30)
        
        return o
    end
    
    -- ===================== FULL MODE =====================
    
    -- Header
    o = "📟 " .. board .. "\n"
    o = o .. "🔧 v" .. version .. " │ ⏱ " .. fmt_uptime(uptime) .. "\n"
    o = o .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    -- System stats
    o = o .. "🖥 CPU " .. progress_bar(cpu, 6) .. " " .. cpu .. "%"
    o = o .. " │ RAM " .. progress_bar(mem, 6) .. " " .. mem .. "%\n"
    
    -- LTE Section
    if lte then
        local status = lte_running and "🟢" or "🔴"
        o = o .. "\n📡 LTE " .. status
        
        if lte_running then
            o = o .. " " .. signal_bars(signal) .. " " .. signal .. "dBm\n"
            if operator ~= "" then
                o = o .. "   " .. operator
                if tech ~= "" then o = o .. " │ " .. tech end
                o = o .. "\n"
            end
            o = o .. "   ↓ " .. fmt_speed(down_speed * 8) .. "/s"
            o = o .. "  ↑ " .. fmt_speed(up_speed * 8) .. "/s\n"
        else
            o = o .. " Disconnected\n"
        end
    end
    
    -- Speed Graphs
    o = o .. "\n📊 SPEED HISTORY\n"
    
    local max_down = 0
    for i = 1, #state.hist_down do
        if state.hist_down[i] and state.hist_down[i] > max_down then
            max_down = state.hist_down[i]
        end
    end
    o = o .. "↓ " .. mini_graph(state.hist_down, CONFIG.graph_width) .. " " .. fmt_speed(max_down) .. "\n"
    
    local max_up = 0
    for i = 1, #state.hist_up do
        if state.hist_up[i] and state.hist_up[i] > max_up then
            max_up = state.hist_up[i]
        end
    end
    o = o .. "↑ " .. mini_graph(state.hist_up, CONFIG.graph_width) .. " " .. fmt_speed(max_up) .. "\n"
    
    -- Signal graph (if LTE)
    if lte and #state.hist_signal > 0 then
        local sig_norm = {}
        for i = 1, #state.hist_signal do
            sig_norm[i] = (state.hist_signal[i] or -100) + 110
        end
        o = o .. "📶 " .. mini_graph(sig_norm, CONFIG.graph_width) .. " " .. signal .. "dBm\n"
    end
    
    -- Data Usage
    o = o .. "\n📈 DATA USAGE\n"
    local daily_pct = math.min(100, (state.today_bytes / (CONFIG.daily_limit_gb * 1e9)) * 100)
    local month_pct = math.min(100, (state.month_bytes / (CONFIG.monthly_limit_gb * 1e9)) * 100)
    
    o = o .. "Today " .. progress_bar(daily_pct, 8) .. " " .. fmt_bytes(state.today_bytes)
    o = o .. "/" .. CONFIG.daily_limit_gb .. "GB\n"
    o = o .. "Month " .. progress_bar(month_pct, 8) .. " " .. fmt_bytes(state.month_bytes)
    o = o .. "/" .. CONFIG.monthly_limit_gb .. "GB\n"
    
    -- Clients Section
    if client_count > 0 and state.hotspot_clients then
        o = o .. "\n👥 HOTSPOT CLIENTS (" .. client_count .. ")\n"
        
        local shown = 0
        for i = 1, #state.hotspot_clients do
            if shown >= CONFIG.max_clients then break end
            
            local client = state.hotspot_clients[i]
            if client and type(client) == "table" then
                local name = tostring(client["user"] or "unknown"):sub(1, 12)
                local bytes_in = tonumber(client["bytes-in"]) or 0
                local bytes_out = tonumber(client["bytes-out"]) or 0
                local total = bytes_in + bytes_out
                local up = client["uptime"] or ""
                
                o = o .. "• " .. name
                o = o .. " │ " .. fmt_bytes(total)
                if up ~= "" then
                    o = o .. " │ " .. fmt_uptime(up)
                end
                o = o .. "\n"
                
                shown = shown + 1
            end
        end
        
        if client_count > CONFIG.max_clients then
            o = o .. "  +" .. (client_count - CONFIG.max_clients) .. " more...\n"
        end
    end
    
    return o
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

function on_resume()
    ui:show_text("⏳ Connecting to " .. CONFIG.ip .. "...\n\nFetching:\n• System info\n• Interfaces\n• LTE status\n• Clients\n• DHCP leases")
    
    last_error = ""  -- Clear previous errors
    
    collect_data(function()
        local display = generate_display()
        ui:show_text(display)
    end)
end

function on_click()
    system:open_browser("http://" .. CONFIG.ip .. "/webfig/")
end

function on_long_click()
    ui:show_context_menu({
        "📊 Toggle Compact/Full",
        "🔄 Refresh Now",
        "━━━━━━━━━━━━━━",
        "📡 Enable LTE",
        "📴 Disable LTE",
        "🔌 Enable Hotspot",
        "📵 Disable Hotspot",
        "━━━━━━━━━━━━━━",
        "🔄 Reboot Router",
        "🗑️ Reset Data Stats",
        "❌ Cancel"
    })
end

function on_context_menu_click(idx)
    if idx == 1 then
        -- Toggle mode
        state.mode = (state.mode == "compact") and "full" or "compact"
        on_resume()
        
    elseif idx == 2 then
        -- Refresh
        on_resume()
        
    elseif idx == 4 then
        -- Enable LTE
        api_post("/interface/enable", {numbers = CONFIG.lte_interface}, function(ok)
            system:toast(ok and "LTE enabled" or "Failed to enable LTE")
            on_resume()
        end)
        
    elseif idx == 5 then
        -- Disable LTE
        api_post("/interface/disable", {numbers = CONFIG.lte_interface}, function(ok)
            system:toast(ok and "LTE disabled" or "Failed to disable LTE")
            on_resume()
        end)
        
    elseif idx == 6 then
        -- Enable Hotspot
        api_post("/interface/enable", {numbers = CONFIG.hotspot_interface}, function(ok)
            system:toast(ok and "Hotspot enabled" or "Failed to enable Hotspot")
            on_resume()
        end)
        
    elseif idx == 7 then
        -- Disable Hotspot
        api_post("/interface/disable", {numbers = CONFIG.hotspot_interface}, function(ok)
            system:toast(ok and "Hotspot disabled" or "Failed to disable Hotspot")
            on_resume()
        end)
        
    elseif idx == 9 then
        -- Reboot
        api_post("/system/reboot", {}, function(ok)
            system:toast(ok and "Router rebooting..." or "Failed to reboot")
        end)
        
    elseif idx == 10 then
        -- Reset stats
        state.today_bytes = 0
        state.month_bytes = 0
        state.hist_down = {}
        state.hist_up = {}
        state.hist_signal = {}
        state.hist_cpu = {}
        system:toast("Stats reset")
        on_resume()
    end
end

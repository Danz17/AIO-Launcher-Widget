-- Network Traffic Graph Widget for AIO Launcher
-- Real-time network speed visualization with MikroTik integration
-- Uses: http:get(), storage, ui:show_chart()

-- Configuration - MikroTik Router Settings
local ROUTER_IP = "10.1.1.1"
local ROUTER_USER = "admin"
local ROUTER_PASS = "admin123"
local INTERFACE = "ether1"  -- Interface to monitor

local MAX_HISTORY = 30  -- Data points for graph
local STORAGE_KEY = "network_traffic_history"
local REFRESH_INTERVAL = 5  -- Seconds (for reference, widget refreshes on_resume)

-- State
local download_history = {}
local upload_history = {}
local current_download = 0
local current_upload = 0
local peak_download = 0
local peak_upload = 0
local last_rx_bytes = 0
local last_tx_bytes = 0
local last_time = 0

-- Helper functions
local function load_history()
    local data = storage:get(STORAGE_KEY)
    if data then
        local decoded = json.decode(data)
        if decoded then
            return decoded.download or {}, decoded.upload or {}
        end
    end
    return {}, {}
end

local function save_history()
    storage:put(STORAGE_KEY, json.encode({
        download = download_history,
        upload = upload_history
    }))
end

local function add_data_point(history, value, max_size)
    table.insert(history, value)
    if #history > max_size then
        table.remove(history, 1)
    end
    return history
end

local function format_speed(bps)
    if bps >= 1000000000 then
        return string.format("%.1f Gbps", bps / 1000000000)
    elseif bps >= 1000000 then
        return string.format("%.1f Mbps", bps / 1000000)
    elseif bps >= 1000 then
        return string.format("%.1f Kbps", bps / 1000)
    else
        return string.format("%d bps", bps)
    end
end

local function format_bytes(bytes)
    if bytes >= 1099511627776 then
        return string.format("%.2f TB", bytes / 1099511627776)
    elseif bytes >= 1073741824 then
        return string.format("%.2f GB", bytes / 1073741824)
    elseif bytes >= 1048576 then
        return string.format("%.2f MB", bytes / 1048576)
    elseif bytes >= 1024 then
        return string.format("%.2f KB", bytes / 1024)
    else
        return string.format("%d B", bytes)
    end
end

local function get_speed_bar(speed, max_speed)
    if max_speed == 0 then max_speed = 1 end
    local percent = math.min(100, (speed / max_speed) * 100)
    local bars = math.floor(percent / 10)
    local filled = string.rep("█", bars)
    local empty = string.rep("░", 10 - bars)
    return filled .. empty
end

local function get_average(history)
    if #history == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(history) do
        sum = sum + v
    end
    return sum / #history
end

-- Display traffic data
local function show_traffic()
    local lines = {
        "📡 Network Traffic",
        "Interface: " .. INTERFACE,
        ""
    }

    -- Current speeds
    local dl_bar = get_speed_bar(current_download, peak_download)
    local ul_bar = get_speed_bar(current_upload, peak_upload)

    table.insert(lines, "⬇️ Download: " .. format_speed(current_download))
    table.insert(lines, "   " .. dl_bar)
    table.insert(lines, "")
    table.insert(lines, "⬆️ Upload: " .. format_speed(current_upload))
    table.insert(lines, "   " .. ul_bar)

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

    -- Stats
    table.insert(lines, "📊 Statistics:")
    table.insert(lines, "   Peak ⬇️: " .. format_speed(peak_download))
    table.insert(lines, "   Peak ⬆️: " .. format_speed(peak_upload))

    if #download_history > 0 then
        table.insert(lines, "   Avg ⬇️: " .. format_speed(get_average(download_history)))
        table.insert(lines, "   Avg ⬆️: " .. format_speed(get_average(upload_history)))
    end

    table.insert(lines, "")
    table.insert(lines, "📈 Samples: " .. #download_history)

    ui:show_text(table.concat(lines, "\n"))

    -- Show download speed chart
    if #download_history >= 3 then
        -- Scale to Mbps for chart
        local scaled = {}
        for _, v in ipairs(download_history) do
            table.insert(scaled, v / 1000000)  -- Convert to Mbps
        end
        ui:show_chart(scaled, nil, "Download Speed (Mbps)", true)
    end
end

-- Fetch traffic from MikroTik
local function fetch_traffic()
    ui:show_text("⏳ Fetching traffic data...")

    -- Build URL with basic auth
    local url = "http://" .. ROUTER_USER .. ":" .. ROUTER_PASS .. "@" .. ROUTER_IP .. "/rest/interface"

    http:get(url, function(body, code)
        if code == 200 and body then
            local interfaces = json.decode(body)
            if interfaces then
                -- Find our interface
                for _, iface in ipairs(interfaces) do
                    if iface.name == INTERFACE then
                        local rx_bytes = tonumber(iface["rx-byte"]) or 0
                        local tx_bytes = tonumber(iface["tx-byte"]) or 0
                        local current_time = os.time()

                        -- Calculate speed (bytes per second -> bits per second)
                        if last_time > 0 and last_rx_bytes > 0 then
                            local time_diff = current_time - last_time
                            if time_diff > 0 then
                                local rx_diff = rx_bytes - last_rx_bytes
                                local tx_diff = tx_bytes - last_tx_bytes

                                -- Handle counter reset
                                if rx_diff < 0 then rx_diff = rx_bytes end
                                if tx_diff < 0 then tx_diff = tx_bytes end

                                current_download = (rx_diff / time_diff) * 8  -- bits per second
                                current_upload = (tx_diff / time_diff) * 8

                                -- Update peaks
                                if current_download > peak_download then
                                    peak_download = current_download
                                end
                                if current_upload > peak_upload then
                                    peak_upload = current_upload
                                end

                                -- Add to history
                                download_history = add_data_point(download_history, current_download, MAX_HISTORY)
                                upload_history = add_data_point(upload_history, current_upload, MAX_HISTORY)
                                save_history()
                            end
                        end

                        last_rx_bytes = rx_bytes
                        last_tx_bytes = tx_bytes
                        last_time = current_time

                        show_traffic()
                        return
                    end
                end
                ui:show_text("❌ Interface '" .. INTERFACE .. "' not found")
            else
                ui:show_text("❌ Failed to parse response")
            end
        else
            -- Show demo mode with simulated data
            show_demo_mode()
        end
    end)
end

-- Demo mode when MikroTik is not available
local function show_demo_mode()
    -- Generate random demo data
    current_download = math.random(1000000, 100000000)  -- 1-100 Mbps
    current_upload = math.random(500000, 20000000)  -- 0.5-20 Mbps

    if current_download > peak_download then
        peak_download = current_download
    end
    if current_upload > peak_upload then
        peak_upload = current_upload
    end

    download_history = add_data_point(download_history, current_download, MAX_HISTORY)
    upload_history = add_data_point(upload_history, current_upload, MAX_HISTORY)
    save_history()

    local lines = {
        "📡 Network Traffic (Demo Mode)",
        "⚠️ MikroTik not reachable",
        ""
    }

    local dl_bar = get_speed_bar(current_download, peak_download)
    local ul_bar = get_speed_bar(current_upload, peak_upload)

    table.insert(lines, "⬇️ Download: " .. format_speed(current_download))
    table.insert(lines, "   " .. dl_bar)
    table.insert(lines, "")
    table.insert(lines, "⬆️ Upload: " .. format_speed(current_upload))
    table.insert(lines, "   " .. ul_bar)
    table.insert(lines, "")
    table.insert(lines, "📈 Samples: " .. #download_history)

    ui:show_text(table.concat(lines, "\n"))

    if #download_history >= 3 then
        local scaled = {}
        for _, v in ipairs(download_history) do
            table.insert(scaled, v / 1000000)
        end
        ui:show_chart(scaled, nil, "Download (Mbps) - Demo", true)
    end
end

-- Callbacks
function on_resume()
    download_history, upload_history = load_history()
    fetch_traffic()
end

function on_click()
    fetch_traffic()
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Refresh",
        "📊 Show Upload Chart",
        "🗑️ Clear History",
        "⚙️ Show Config"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        fetch_traffic()
    elseif index == 2 then
        -- Show upload chart
        if #upload_history >= 3 then
            local scaled = {}
            for _, v in ipairs(upload_history) do
                table.insert(scaled, v / 1000000)
            end
            ui:show_text("⬆️ Upload Speed History")
            ui:show_chart(scaled, nil, "Upload Speed (Mbps)", true)
        else
            system:toast("Not enough data")
        end
    elseif index == 3 then
        download_history = {}
        upload_history = {}
        peak_download = 0
        peak_upload = 0
        save_history()
        system:toast("History cleared")
        fetch_traffic()
    elseif index == 4 then
        local config = "⚙️ Configuration\n\n"
        config = config .. "Router: " .. ROUTER_IP .. "\n"
        config = config .. "User: " .. ROUTER_USER .. "\n"
        config = config .. "Interface: " .. INTERFACE .. "\n"
        config = config .. "History Size: " .. MAX_HISTORY
        ui:show_text(config)
    end
end

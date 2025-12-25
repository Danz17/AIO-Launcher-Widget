-- Uptime Monitor Widget for AIO Launcher
-- Monitor website/service status with response time graph
-- Uses: http:get(), storage, ui:show_chart()

-- Configuration - Add your endpoints here
local ENDPOINTS = {
    { name = "Google", url = "https://www.google.com", icon = "🔍" },
    { name = "GitHub", url = "https://github.com", icon = "🐙" },
    { name = "Cloudflare", url = "https://1.1.1.1", icon = "☁️" }
}

local MAX_HISTORY = 20  -- Response time samples per endpoint
local STORAGE_KEY = "uptime_history"
local TIMEOUT = 10000  -- 10 seconds

-- State
local results = {}
local response_history = {}
local pending_checks = 0
local check_start_times = {}

-- Helper functions
local function load_history()
    local data = storage:get(STORAGE_KEY)
    if data then
        local decoded = json.decode(data)
        if decoded then
            return decoded
        end
    end
    return {}
end

local function save_history(history)
    storage:put(STORAGE_KEY, json.encode(history))
end

local function add_response_time(endpoint_name, response_time)
    if not response_history[endpoint_name] then
        response_history[endpoint_name] = {}
    end
    table.insert(response_history[endpoint_name], response_time)
    if #response_history[endpoint_name] > MAX_HISTORY then
        table.remove(response_history[endpoint_name], 1)
    end
end

local function get_average_response(endpoint_name)
    local history = response_history[endpoint_name]
    if not history or #history == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(history) do
        sum = sum + v
    end
    return math.floor(sum / #history)
end

local function get_status_icon(status, response_time)
    if status == "up" then
        if response_time < 200 then
            return "🟢"  -- Fast
        elseif response_time < 500 then
            return "🟡"  -- Medium
        else
            return "🟠"  -- Slow
        end
    else
        return "🔴"  -- Down
    end
end

local function format_response_time(ms)
    if ms < 1000 then
        return ms .. "ms"
    else
        return string.format("%.1fs", ms / 1000)
    end
end

-- Display results
local function show_results()
    if pending_checks > 0 then
        ui:show_text("⏳ Checking " .. pending_checks .. " endpoints...")
        return
    end

    local lines = { "📡 Uptime Monitor", "" }

    -- Count stats
    local up_count = 0
    local total_count = #ENDPOINTS

    for _, endpoint in ipairs(ENDPOINTS) do
        local result = results[endpoint.name]
        if result then
            local status_icon = get_status_icon(result.status, result.response_time)
            local time_str = result.status == "up" and format_response_time(result.response_time) or "timeout"
            local avg = get_average_response(endpoint.name)

            table.insert(lines, endpoint.icon .. " " .. endpoint.name)
            table.insert(lines, "   " .. status_icon .. " " .. time_str .. " (avg: " .. avg .. "ms)")

            if result.status == "up" then
                up_count = up_count + 1
            end
        else
            table.insert(lines, endpoint.icon .. " " .. endpoint.name)
            table.insert(lines, "   ⚪ Not checked")
        end
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "✅ " .. up_count .. "/" .. total_count .. " endpoints online")

    ui:show_text(table.concat(lines, "\n"))

    -- Show response time chart for first endpoint with history
    for _, endpoint in ipairs(ENDPOINTS) do
        local history = response_history[endpoint.name]
        if history and #history >= 3 then
            ui:show_chart(history, nil, endpoint.name .. " Response Time", true)
            break  -- Only show one chart
        end
    end
end

-- Check single endpoint
local function check_endpoint(endpoint, index)
    check_start_times[endpoint.name] = os.time() * 1000  -- Approximate ms

    -- Create unique callback name
    local callback_name = "uptime_" .. index

    -- Define success callback
    _G["on_network_result_" .. callback_name] = function(body, code)
        local end_time = os.time() * 1000
        local response_time = end_time - (check_start_times[endpoint.name] or end_time)

        -- Estimate response time (since we can't get precise timing)
        -- Use a reasonable estimate based on success
        if code and code >= 200 and code < 400 then
            results[endpoint.name] = {
                status = "up",
                response_time = math.max(50, math.min(response_time, 5000)),
                code = code
            }
            add_response_time(endpoint.name, results[endpoint.name].response_time)
        else
            results[endpoint.name] = {
                status = "down",
                response_time = 0,
                code = code or 0
            }
            add_response_time(endpoint.name, 9999)  -- Mark as timeout
        end

        pending_checks = pending_checks - 1
        if pending_checks <= 0 then
            save_history(response_history)
            show_results()
        end
    end

    -- Define error callback
    _G["on_network_error_" .. callback_name] = function(error_msg)
        results[endpoint.name] = {
            status = "down",
            response_time = 0,
            error = error_msg
        }
        add_response_time(endpoint.name, 9999)

        pending_checks = pending_checks - 1
        if pending_checks <= 0 then
            save_history(response_history)
            show_results()
        end
    end

    -- Make request
    http:get(endpoint.url, function(body, code)
        _G["on_network_result_" .. callback_name](body, code)
    end)
end

-- Check all endpoints
local function check_all()
    pending_checks = #ENDPOINTS
    results = {}

    ui:show_text("⏳ Checking " .. #ENDPOINTS .. " endpoints...")

    for i, endpoint in ipairs(ENDPOINTS) do
        check_endpoint(endpoint, i)
    end
end

-- Callbacks
function on_resume()
    response_history = load_history()
    check_all()
end

function on_click()
    check_all()
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Refresh All",
        "🗑️ Clear History",
        "📊 Show All Charts"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        check_all()
    elseif index == 2 then
        response_history = {}
        save_history(response_history)
        system:toast("History cleared")
        check_all()
    elseif index == 3 then
        -- Show stats for all endpoints
        local lines = { "📊 Response Time History", "" }
        for _, endpoint in ipairs(ENDPOINTS) do
            local history = response_history[endpoint.name]
            if history and #history > 0 then
                local avg = get_average_response(endpoint.name)
                local min_val = math.min(table.unpack(history))
                local max_val = math.max(table.unpack(history))
                table.insert(lines, endpoint.icon .. " " .. endpoint.name)
                table.insert(lines, "   Avg: " .. avg .. "ms | Min: " .. min_val .. "ms | Max: " .. max_val .. "ms")
                table.insert(lines, "   Samples: " .. #history)
                table.insert(lines, "")
            end
        end
        ui:show_text(table.concat(lines, "\n"))
    end
end

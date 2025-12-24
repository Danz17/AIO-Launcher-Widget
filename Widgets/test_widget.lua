-- name = "API Test"
-- description = "Test widget to verify AIO API"
-- type = "widget"

local debug_info = ""

function on_resume()
    debug_info = ""
    ui:show_text("API Test Widget\n\nTap to test HTTP\nLong press for menu")
end

function on_click()
    debug_info = "Request sent: " .. os.date("%H:%M:%S") .. "\n"
    ui:show_text("Loading...\n\n" .. debug_info)
    http:get("https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT")
end

function on_network_result(body, code)
    debug_info = debug_info .. "Response: " .. os.date("%H:%M:%S") .. "\n"
    debug_info = debug_info .. "Code: " .. tostring(code) .. "\n"
    debug_info = debug_info .. "Body length: " .. tostring(body and #body or 0) .. "\n"

    if code == 200 and body then
        local ok, data = pcall(function() return json:decode(body) end)
        if ok and data then
            ui:show_text("SUCCESS!\n\nBTC: $" .. (data.price or "?") .. "\n\n" .. debug_info)
        else
            ui:show_text("JSON Error\n\n" .. debug_info .. "\nBody: " .. tostring(body):sub(1, 100))
        end
    else
        ui:show_text("HTTP Error\n\n" .. debug_info .. "\nBody: " .. tostring(body):sub(1, 100))
    end
end

function on_network_error(err)
    debug_info = debug_info .. "Error: " .. os.date("%H:%M:%S") .. "\n"
    ui:show_text("Network Error\n\n" .. debug_info .. "\nError: " .. tostring(err))
end

function on_long_click()
    ui:show_context_menu({
        { "refresh", "Refresh" },
        { "info", "Info" },
        { "close", "Close" }
    })
end

function on_context_menu_click(idx)
    ui:show_toast("Selected: " .. tostring(idx))
end

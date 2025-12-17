-- name = "MikroTik Monitor"
-- description = "Router monitoring"
-- author = "Alaa"
-- foldable = "true"

-- CONFIGURATION
-- To generate Base64 auth: echo -n "username:password" | base64
local CONFIG = {
    ip = "10.1.1.1",
    auth = "Basic YWRtaW46YWRtaW4xMjM="
}

function on_resume()
    local url = "http://" .. CONFIG.ip .. "/rest/system/resource"
    
    ui:show_text("⏳ Connecting...")
    
    -- Try method 1: headers as third param table
    http:get(url, function(data, code)
        if data and data ~= "" then
            local ok, res = pcall(function() return json:decode(data) end)
            if ok and res then
                show_result(res)
                return
            end
        end
        
        -- If failed, show debug info
        ui:show_text("❌ Auth failed\n\nCode: " .. tostring(code) .. "\n\nTry enabling REST API:\nSystem → Users → admin\nEnable 'api' permission")
        
    end, {Authorization = CONFIG.auth})
end

function show_result(res)
    local cpu = res["cpu-load"] or "?"
    local mem_free = tonumber(res["free-memory"]) or 0
    local mem_total = tonumber(res["total-memory"]) or 1
    local mem = math.floor((1 - mem_free / mem_total) * 100)
    local uptime = res["uptime"] or "?"
    local board = res["board-name"] or "MikroTik"
    local version = res["version"] or "?"
    
    local o = "📟 " .. board .. "\n"
    o = o .. "🔧 RouterOS " .. version .. "\n"
    o = o .. "⏱ Uptime: " .. uptime .. "\n"
    o = o .. "🖥 CPU: " .. cpu .. "%\n"
    o = o .. "💾 RAM: " .. mem .. "%\n"
    o = o .. "\n✅ Connected!"
    
    ui:show_text(o)
end

function on_click()
    system:open_browser("http://" .. CONFIG.ip .. "/webfig/")
end

function on_long_click()
    on_resume()
end


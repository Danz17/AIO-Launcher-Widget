-- name = "MikroTik Monitor"
-- description = "Router monitoring"
-- author = "Alaa"
-- foldable = "true"

-- EDIT YOUR CREDENTIALS HERE
local IP = "10.1.1.1"
local USER = "admin"  
local PASS = "admin123"

function on_resume()
    local url = "http://" .. USER .. ":" .. PASS .. "@" .. IP .. "/rest/system/resource"
    
    ui:show_text("⏳ Connecting...")
    
    http:get(url, function(data)
        if not data or data == "" then
            ui:show_text("❌ No response from " .. IP)
            return
        end
        
        local ok, res = pcall(function() return json:decode(data) end)
        if not ok or not res then
            ui:show_text("❌ Parse error")
            return
        end
        
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
        
        ui:show_text(o)
    end)
end

function on_click()
    system:open_browser("http://" .. IP .. "/webfig/")
end

function on_long_click()
    on_resume()
end

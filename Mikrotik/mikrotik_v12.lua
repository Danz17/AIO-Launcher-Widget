-- name = "MikroTik Monitor"
-- description = "Router monitoring"
-- author = "Alaa"
-- foldable = "true"

local IP = "10.1.1.1"
local AUTH = "Basic YWRtaW46YWRtaW4xMjM="

function on_resume()
    local url = "http://" .. IP .. "/rest/system/resource"
    
    ui:show_text("⏳ Testing connection...")
    
    -- Method: Try passing auth in different ways
    local headers = {
        Authorization = AUTH
    }
    
    -- AIO Launcher might use different http signature
    -- Try: http:get(url, body, callback, headers)
    -- or: http:get(url, callback, timeout, headers)
    
    http:get(url, "", function(data, code)
        if not data or data == "" then
            ui:show_text("❌ Empty response\nHTTP Code: " .. tostring(code))
            return
        end
        
        -- Check if we got HTML (login page) instead of JSON
        if string.find(data, "<html") or string.find(data, "<HTML") then
            ui:show_text("❌ Got login page\nHeaders not sent\n\nAIO can't do auth :(")
            return
        end
        
        -- Check for 401
        if string.find(data, "401") or string.find(data, "error") then
            ui:show_text("❌ Auth error:\n" .. string.sub(data, 1, 150))
            return
        end
        
        local ok, res = pcall(function() return json:decode(data) end)
        if not ok or not res then
            ui:show_text("📄 Raw response:\n" .. string.sub(data, 1, 300))
            return
        end
        
        -- SUCCESS!
        local cpu = res["cpu-load"] or "?"
        local mem_free = tonumber(res["free-memory"]) or 0
        local mem_total = tonumber(res["total-memory"]) or 1
        local mem = math.floor((1 - mem_free / mem_total) * 100)
        local uptime = res["uptime"] or "?"
        local board = res["board-name"] or "MikroTik"
        
        local o = "✅ " .. board .. "\n"
        o = o .. "⏱ " .. uptime .. "\n"
        o = o .. "🖥 CPU: " .. cpu .. "% │ RAM: " .. mem .. "%"
        
        ui:show_text(o)
        
    end, headers)
end

function on_click()
    system:open_browser("http://" .. IP .. "/webfig/")
end

function on_long_click()
    on_resume()
end

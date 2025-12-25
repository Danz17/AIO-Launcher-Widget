-- name = "Hello World"
-- description = "Simple test widget for AIO Launcher Emulator"
-- author = "Phenix"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- Simple Hello World Widget
-- Demonstrates basic AIO Launcher APIs
-- ============================================================================

local counter = 0

function on_resume()
  ui:show_text("👋 Hello World!\n\nTap to count\nLong press for menu")
end

function on_click()
  counter = counter + 1
  ui:show_text("👋 Hello World!\n\n🔢 Count: " .. counter .. "\n\nTap to increment")
end

function on_long_click()
  ui:show_context_menu({
    { "🔄 Reset Counter", "reset" },
    { "📋 Copy Count", "copy" },
    { "🌐 Open GitHub", "github" }
  }, "on_menu")
end

function on_menu(idx)
  if idx == 1 then
    counter = 0
    ui:show_text("👋 Hello World!\n\n🔢 Counter reset!")
  elseif idx == 2 then
    system:copy_to_clipboard(tostring(counter))
    system:toast("Copied: " .. counter)
  elseif idx == 3 then
    system:open_browser("https://github.com/Danz17/AIO-Launcher-Widget")
  end
end

-- name = "Quick Notes"
-- description = "Simple note-taking widget with history"
-- author = "Phenix"
-- type = "widget"
-- data_source = "script"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local CONFIG = {
  max_history = 10,
  max_display_length = 100,
  show_timestamp = true
}

-- Storage keys
local KEY_CURRENT = "quicknotes_current"
local KEY_HISTORY = "quicknotes_history"

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end

local function get_current_note()
  local note = storage:get(KEY_CURRENT)
  return note or ""
end

local function save_note(text)
  if not text or text == "" then return end

  -- Save as current
  storage:put(KEY_CURRENT, text)

  -- Add to history
  local history = safe_decode(storage:get(KEY_HISTORY)) or {}

  -- Add new note at beginning
  table.insert(history, 1, {
    text = text,
    time = os.time()
  })

  -- Trim history
  while #history > CONFIG.max_history do
    table.remove(history)
  end

  storage:put(KEY_HISTORY, json.encode(history))
end

local function get_history()
  local data = storage:get(KEY_HISTORY)
  return safe_decode(data) or {}
end

local function clear_current()
  storage:delete(KEY_CURRENT)
end

local function format_time(timestamp)
  if not timestamp then return "" end
  local diff = os.time() - timestamp
  if diff < 60 then return "just now"
  elseif diff < 3600 then return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then return math.floor(diff / 3600) .. "h ago"
  else return math.floor(diff / 86400) .. "d ago"
  end
end

local function truncate(text, max_len)
  if not text then return "" end
  if #text <= max_len then return text end
  return text:sub(1, max_len - 3) .. "..."
end

-- ============================================================================
-- DISPLAY
-- ============================================================================
local function render()
  local note = get_current_note()
  local lines = {}

  if note == "" then
    table.insert(lines, "📝 Quick Notes")
    table.insert(lines, "")
    table.insert(lines, "No note saved")
    table.insert(lines, "")
    table.insert(lines, "Tap to add a note")
  else
    table.insert(lines, "📝 Quick Notes")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "")
    table.insert(lines, truncate(note, CONFIG.max_display_length))
    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "Tap to edit │ Long press for menu")
  end

  ui:show_text(table.concat(lines, "\n"))
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================
function on_resume()
  render()
end

function on_click()
  local current = get_current_note()
  -- In AIO Launcher, this would open an input dialog
  -- For now, we'll show a prompt to use long-press menu
  system:toast("Long press to add/edit note")
  render()
end

function on_long_click()
  local history = get_history()
  local menu = {
    { "✏️ New Note", "new" },
    { "📋 Copy Note", "copy" },
    { "🗑️ Clear Note", "clear" }
  }

  if #history > 0 then
    table.insert(menu, { "━━━━━━━━━━", "" })
    table.insert(menu, { "📜 History (" .. #history .. ")", "history" })
  end

  ui:show_context_menu(menu, "on_menu")
end

function on_menu(idx)
  if idx == 1 then
    -- New note - in real AIO Launcher this would open input
    local sample_notes = {
      "Remember to check the router",
      "Meeting at 3pm",
      "Call back tomorrow",
      "Buy groceries",
      "Update the widget code"
    }
    local random_note = sample_notes[math.random(#sample_notes)]
    save_note(random_note)
    system:toast("Note saved (demo)")
    render()
  elseif idx == 2 then
    local note = get_current_note()
    if note ~= "" then
      system:copy_to_clipboard(note)
      system:toast("Copied to clipboard")
    else
      system:toast("No note to copy")
    end
  elseif idx == 3 then
    clear_current()
    system:toast("Note cleared")
    render()
  elseif idx == 5 then
    -- Show history
    local history = get_history()
    if #history > 0 then
      local lines = {"📜 Note History\n"}
      for i, item in ipairs(history) do
        if i > 5 then break end
        local time_str = CONFIG.show_timestamp and " (" .. format_time(item.time) .. ")" or ""
        table.insert(lines, i .. ". " .. truncate(item.text, 40) .. time_str)
      end
      ui:show_text(table.concat(lines, "\n"))
    end
  end
end

-- Initialize
render()

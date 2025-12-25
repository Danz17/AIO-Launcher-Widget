-- Calendar Events Widget for AIO Launcher
-- Display upcoming events from iCal feeds or manual entries
-- Uses: http:get(), storage, ui:show_text()

-- Configuration
local STORAGE_KEY = "calendar_events_data"
local MAX_EVENTS = 20
local REFRESH_MINUTES = 30

-- iCal feeds (public calendars)
local ICAL_FEEDS = {
  -- Add your iCal URLs here
  -- { name = "Work", url = "https://calendar.google.com/calendar/ical/xxx/public/basic.ics" },
  -- { name = "Holidays", url = "https://www.officeholidays.com/ics/usa" }
}

-- State
local events = {}
local manual_events = {}
local last_refresh = 0
local view_mode = "upcoming"  -- upcoming, today, week, all

-- Helper functions
local function load_data()
  local data = storage:get(STORAGE_KEY)
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return { manual_events = {}, last_refresh = 0 }
end

local function save_data()
  storage:put(STORAGE_KEY, json.encode({
    manual_events = manual_events,
    last_refresh = last_refresh
  }))
end

local function get_today()
  return os.date("%Y-%m-%d")
end

local function get_now()
  return os.date("%Y-%m-%d %H:%M")
end

local function truncate(str, len)
  if not str then return "" end
  if #str <= len then return str end
  return str:sub(1, len - 2) .. ".."
end

-- Parse iCal date format (YYYYMMDD or YYYYMMDDTHHMMSS)
local function parse_ical_date(date_str)
  if not date_str then return nil end

  -- Remove timezone suffix
  date_str = date_str:gsub("Z$", "")

  local y, m, d, h, mi, s

  -- Full datetime: YYYYMMDDTHHMMSS
  y, m, d, h, mi, s = date_str:match("(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)")
  if y then
    return string.format("%s-%s-%s %s:%s", y, m, d, h, mi)
  end

  -- Date only: YYYYMMDD
  y, m, d = date_str:match("(%d%d%d%d)(%d%d)(%d%d)")
  if y then
    return string.format("%s-%s-%s", y, m, d)
  end

  return nil
end

-- Parse iCal feed
local function parse_ical(ical_text, source_name)
  local parsed_events = {}
  local current_event = nil

  for line in ical_text:gmatch("[^\r\n]+") do
    -- Handle line continuations
    if line:match("^%s") and current_event then
      -- Continuation of previous line
      if current_event.last_field then
        current_event[current_event.last_field] = (current_event[current_event.last_field] or "") .. line:gsub("^%s+", "")
      end
    elseif line:match("^BEGIN:VEVENT") then
      current_event = { source = source_name }
    elseif line:match("^END:VEVENT") and current_event then
      -- Only add future events
      if current_event.start_date and current_event.start_date >= get_today() then
        table.insert(parsed_events, {
          title = current_event.summary or "Untitled",
          start = current_event.start_date,
          end_date = current_event.end_date,
          location = current_event.location,
          description = current_event.description,
          source = source_name,
          all_day = not current_event.start_date:match(" ")
        })
      end
      current_event = nil
    elseif current_event then
      local key, value = line:match("^([^:;]+)[;:](.+)")
      if key and value then
        key = key:upper()
        if key == "SUMMARY" then
          current_event.summary = value
          current_event.last_field = "summary"
        elseif key == "DTSTART" or key:match("^DTSTART") then
          current_event.start_date = parse_ical_date(value)
          current_event.last_field = "start_date"
        elseif key == "DTEND" or key:match("^DTEND") then
          current_event.end_date = parse_ical_date(value)
          current_event.last_field = "end_date"
        elseif key == "LOCATION" then
          current_event.location = value
          current_event.last_field = "location"
        elseif key == "DESCRIPTION" then
          current_event.description = value
          current_event.last_field = "description"
        end
      end
    end
  end

  return parsed_events
end

-- Calculate time until event
local function get_countdown(event_date)
  if not event_date then return "" end

  local now = get_now()
  local today = get_today()

  -- Extract date part
  local event_day = event_date:match("^%d%d%d%d%-%d%d%-%d%d")
  if not event_day then return "" end

  if event_day == today then
    local event_time = event_date:match(" (%d%d:%d%d)")
    if event_time then
      return "Today " .. event_time
    else
      return "Today"
    end
  end

  -- Calculate days
  local ey, em, ed = event_day:match("(%d+)-(%d+)-(%d+)")
  local ty, tm, td = today:match("(%d+)-(%d+)-(%d+)")

  if ey and ty then
    local event_time = os.time({ year = ey, month = em, day = ed })
    local today_time = os.time({ year = ty, month = tm, day = td })
    local diff = math.floor((event_time - today_time) / 86400)

    if diff == 1 then return "Tomorrow"
    elseif diff <= 7 then return "In " .. diff .. " days"
    elseif diff <= 30 then return "In " .. math.floor(diff / 7) .. " weeks"
    else return event_day end
  end

  return event_day
end

-- Get event icon based on title/type
local function get_event_icon(event)
  local title = (event.title or ""):lower()

  if title:match("birthday") or title:match("bday") then return "🎂"
  elseif title:match("meeting") or title:match("call") then return "📞"
  elseif title:match("deadline") or title:match("due") then return "⏰"
  elseif title:match("holiday") or title:match("vacation") then return "🏖️"
  elseif title:match("doctor") or title:match("appointment") then return "🏥"
  elseif title:match("flight") or title:match("travel") then return "✈️"
  elseif title:match("dinner") or title:match("lunch") or title:match("breakfast") then return "🍽️"
  elseif title:match("gym") or title:match("workout") then return "💪"
  elseif title:match("party") or title:match("celebration") then return "🎉"
  else return "📅" end
end

-- Filter events
local function get_filtered_events()
  local all = {}

  -- Combine iCal events and manual events
  for _, e in ipairs(events) do
    table.insert(all, e)
  end
  for _, e in ipairs(manual_events) do
    table.insert(all, e)
  end

  -- Filter by view mode
  local today = get_today()
  local filtered = {}

  for _, e in ipairs(all) do
    local event_day = (e.start or ""):match("^%d%d%d%d%-%d%d%-%d%d") or ""

    if view_mode == "today" then
      if event_day == today then
        table.insert(filtered, e)
      end
    elseif view_mode == "week" then
      -- Check if within 7 days
      if event_day >= today then
        local ey, em, ed = event_day:match("(%d+)-(%d+)-(%d+)")
        local ty, tm, td = today:match("(%d+)-(%d+)-(%d+)")
        if ey and ty then
          local event_time = os.time({ year = ey, month = em, day = ed })
          local today_time = os.time({ year = ty, month = tm, day = td })
          local diff = (event_time - today_time) / 86400
          if diff <= 7 then
            table.insert(filtered, e)
          end
        end
      end
    elseif view_mode == "upcoming" then
      if event_day >= today then
        table.insert(filtered, e)
      end
    else
      table.insert(filtered, e)
    end
  end

  -- Sort by date
  table.sort(filtered, function(a, b)
    return (a.start or "") < (b.start or "")
  end)

  return filtered
end

-- Display functions
local function render()
  local lines = {}

  table.insert(lines, "📅 Calendar Events")

  -- View mode indicator
  local mode_name = view_mode == "upcoming" and "Upcoming" or
                    view_mode == "today" and "Today" or
                    view_mode == "week" and "This Week" or "All"
  table.insert(lines, "🔍 " .. mode_name)
  table.insert(lines, "")

  local filtered = get_filtered_events()

  if #filtered == 0 then
    if #events == 0 and #manual_events == 0 then
      table.insert(lines, "No events scheduled")
      table.insert(lines, "")
      if #ICAL_FEEDS == 0 then
        table.insert(lines, "Add iCal feeds in widget")
        table.insert(lines, "or long press to add event")
      else
        table.insert(lines, "Tap to refresh feeds")
      end
    else
      table.insert(lines, "No events for this view")
    end
  else
    local shown = 0
    for _, event in ipairs(filtered) do
      if shown >= 6 then
        table.insert(lines, string.format("   ... +%d more", #filtered - shown))
        break
      end

      local icon = get_event_icon(event)
      local title = truncate(event.title, 22)
      local countdown = get_countdown(event.start)

      table.insert(lines, icon .. " " .. title)
      table.insert(lines, "   " .. countdown)

      shown = shown + 1
    end
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

  -- Stats
  local today_count = 0
  local week_count = 0
  local today = get_today()

  for _, e in ipairs(get_filtered_events()) do
    local event_day = (e.start or ""):match("^%d%d%d%d%-%d%d%-%d%d") or ""
    if event_day == today then
      today_count = today_count + 1
    end
    -- Week count
    if event_day >= today then
      local ey, em, ed = event_day:match("(%d+)-(%d+)-(%d+)")
      local ty, tm, td = today:match("(%d+)-(%d+)-(%d+)")
      if ey and ty then
        local event_time = os.time({ year = ey, month = em, day = ed })
        local today_time = os.time({ year = ty, month = tm, day = td })
        if (event_time - today_time) / 86400 <= 7 then
          week_count = week_count + 1
        end
      end
    end
  end

  table.insert(lines, "📊 Today: " .. today_count .. " | Week: " .. week_count)

  ui:show_text(table.concat(lines, "\n"))
end

-- Fetch iCal feeds
local function fetch_feeds()
  if #ICAL_FEEDS == 0 then
    render()
    return
  end

  events = {}
  local pending = #ICAL_FEEDS

  for _, feed in ipairs(ICAL_FEEDS) do
    http:get(feed.url, function(body, code)
      if code == 200 and body then
        local parsed = parse_ical(body, feed.name)
        for _, e in ipairs(parsed) do
          table.insert(events, e)
        end
      end

      pending = pending - 1
      if pending <= 0 then
        last_refresh = os.time()
        save_data()
        render()
      end
    end)
  end
end

-- Add manual event
local function add_event(title, date, time)
  if not title or title == "" then return end

  local event = {
    title = title,
    start = date .. (time and (" " .. time) or ""),
    source = "Manual",
    all_day = not time
  }

  table.insert(manual_events, event)
  save_data()
  system:toast("Event added!")
  render()
end

-- Delete manual event
local function delete_event(index)
  if manual_events[index] then
    table.remove(manual_events, index)
    save_data()
    system:toast("Event deleted")
    render()
  end
end

-- Callbacks
function on_resume()
  local saved = load_data()
  manual_events = saved.manual_events or {}
  last_refresh = saved.last_refresh or 0

  -- Check if refresh needed
  local elapsed = os.time() - last_refresh
  if elapsed > REFRESH_MINUTES * 60 or #events == 0 then
    fetch_feeds()
  else
    render()
  end
end

function on_click()
  -- Cycle view modes
  if view_mode == "upcoming" then
    view_mode = "today"
  elseif view_mode == "today" then
    view_mode = "week"
  elseif view_mode == "week" then
    view_mode = "all"
  else
    view_mode = "upcoming"
  end
  render()
end

function on_long_click()
  ui:show_context_menu({
    "🔄 Refresh Feeds",
    "➕ Add Event (from clipboard)",
    "━━━━━━━━━━━━━━━━",
    "📅 View Upcoming",
    "📆 View Today",
    "🗓️ View This Week",
    "📋 View All",
    "━━━━━━━━━━━━━━━━",
    "🗑️ Clear Manual Events",
    "⚙️ Settings"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    fetch_feeds()
  elseif index == 2 then
    -- Add event from clipboard
    -- Format: "Event Title | YYYY-MM-DD | HH:MM" or "Event Title | YYYY-MM-DD"
    local clipboard = system:clipboard()
    if clipboard and clipboard ~= "" then
      local title, date, time = clipboard:match("^(.-)%s*|%s*(%d%d%d%d%-%d%d%-%d%d)%s*|?%s*(%d?%d?:?%d?%d?)$")
      if title and date then
        add_event(title, date, time ~= "" and time or nil)
      else
        -- Try just title with today's date
        add_event(clipboard, get_today(), nil)
      end
    else
      system:toast("Copy event: Title | YYYY-MM-DD | HH:MM")
    end
  elseif index == 4 then
    view_mode = "upcoming"
    render()
  elseif index == 5 then
    view_mode = "today"
    render()
  elseif index == 6 then
    view_mode = "week"
    render()
  elseif index == 7 then
    view_mode = "all"
    render()
  elseif index == 9 then
    manual_events = {}
    save_data()
    system:toast("Manual events cleared")
    render()
  elseif index == 10 then
    local settings = "⚙️ Calendar Settings\n\n"
    settings = settings .. "Refresh: " .. REFRESH_MINUTES .. " min\n"
    settings = settings .. "Max Events: " .. MAX_EVENTS .. "\n\n"
    settings = settings .. "━━━━━━━━━━━━━━━━\n"
    settings = settings .. "iCal Feeds: " .. #ICAL_FEEDS .. "\n"
    for i, feed in ipairs(ICAL_FEEDS) do
      settings = settings .. "  " .. i .. ". " .. feed.name .. "\n"
    end
    settings = settings .. "\n━━━━━━━━━━━━━━━━\n"
    settings = settings .. "Manual Events: " .. #manual_events .. "\n\n"
    settings = settings .. "Add Event Format:\n"
    settings = settings .. "Title | YYYY-MM-DD | HH:MM\n"
    settings = settings .. "or just: Title"
    ui:show_text(settings)
  end
end

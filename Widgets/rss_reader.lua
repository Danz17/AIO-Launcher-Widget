-- RSS Reader Widget for AIO Launcher
-- Display headlines from RSS/Atom feeds
-- Uses: http:get(), storage, ui:show_text()

-- Configuration
local CONFIG = {
  max_items = 8,
  refresh_minutes = 30,
  current_feed = 1
}

-- Default feeds (user can customize)
local FEEDS = {
  { name = "TechCrunch", url = "https://techcrunch.com/feed/", icon = "💻" },
  { name = "Hacker News", url = "https://hnrss.org/frontpage", icon = "🔶" },
  { name = "BBC News", url = "https://feeds.bbci.co.uk/news/rss.xml", icon = "📰" },
  { name = "Reddit Tech", url = "https://www.reddit.com/r/technology/.rss", icon = "🤖" },
  { name = "Ars Technica", url = "https://feeds.arstechnica.com/arstechnica/index", icon = "🔬" }
}

local STORAGE_KEY = "rss_reader_data"

-- State
local state = {
  loading = false,
  error = nil,
  items = {},
  last_refresh = 0,
  feed_name = ""
}

-- Helper functions
local function load_data()
  local data = storage:get(STORAGE_KEY)
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return { current_feed = 1, items = {}, last_refresh = 0 }
end

local function save_data()
  storage:put(STORAGE_KEY, json.encode({
    current_feed = CONFIG.current_feed,
    items = state.items,
    last_refresh = state.last_refresh
  }))
end

local function truncate(str, len)
  if not str then return "" end
  str = str:gsub("[\n\r]+", " ")  -- Remove newlines
  str = str:gsub("%s+", " ")      -- Collapse whitespace
  str = str:gsub("^%s+", "")      -- Trim leading
  str = str:gsub("%s+$", "")      -- Trim trailing
  if #str <= len then return str end
  return str:sub(1, len - 2) .. ".."
end

local function decode_html_entities(str)
  if not str then return "" end
  str = str:gsub("&amp;", "&")
  str = str:gsub("&lt;", "<")
  str = str:gsub("&gt;", ">")
  str = str:gsub("&quot;", '"')
  str = str:gsub("&#39;", "'")
  str = str:gsub("&apos;", "'")
  str = str:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
  return str
end

local function strip_html(str)
  if not str then return "" end
  str = str:gsub("<[^>]+>", "")
  return decode_html_entities(str)
end

-- Parse RSS/Atom XML (simple pattern matching)
local function parse_feed(xml)
  local items = {}

  -- Try RSS format first (item tags)
  for item in xml:gmatch("<item[^>]*>(.-)</item>") do
    local title = item:match("<title[^>]*><!%[CDATA%[(.-)%]%]>") or
                  item:match("<title[^>]*>(.-)</title>")
    local link = item:match("<link[^>]*>(.-)</link>") or
                 item:match("<link[^>]*href=\"([^\"]+)\"")
    local desc = item:match("<description[^>]*><!%[CDATA%[(.-)%]%]>") or
                 item:match("<description[^>]*>(.-)</description>")
    local pubDate = item:match("<pubDate[^>]*>(.-)</pubDate>")

    if title then
      table.insert(items, {
        title = strip_html(title),
        link = strip_html(link or ""),
        description = strip_html(desc or ""),
        date = pubDate or ""
      })
    end
  end

  -- If no RSS items, try Atom format (entry tags)
  if #items == 0 then
    for entry in xml:gmatch("<entry[^>]*>(.-)</entry>") do
      local title = entry:match("<title[^>]*><!%[CDATA%[(.-)%]%]>") or
                    entry:match("<title[^>]*>(.-)</title>")
      local link = entry:match("<link[^>]*href=\"([^\"]+)\"") or
                   entry:match("<link[^>]*>(.-)</link>")
      local summary = entry:match("<summary[^>]*><!%[CDATA%[(.-)%]%]>") or
                      entry:match("<summary[^>]*>(.-)</summary>") or
                      entry:match("<content[^>]*><!%[CDATA%[(.-)%]%]>") or
                      entry:match("<content[^>]*>(.-)</content>")
      local updated = entry:match("<updated[^>]*>(.-)</updated>") or
                      entry:match("<published[^>]*>(.-)</published>")

      if title then
        table.insert(items, {
          title = strip_html(title),
          link = strip_html(link or ""),
          description = strip_html(summary or ""),
          date = updated or ""
        })
      end
    end
  end

  return items
end

-- Display functions
local function render()
  if state.loading then
    local feed = FEEDS[CONFIG.current_feed]
    ui:show_text("📡 Loading " .. (feed and feed.name or "feed") .. "...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\n\nTap to retry")
    return
  end

  local feed = FEEDS[CONFIG.current_feed]
  local lines = {}

  table.insert(lines, (feed and feed.icon or "📰") .. " " .. (feed and feed.name or "RSS Feed"))
  table.insert(lines, "")

  if #state.items == 0 then
    table.insert(lines, "No items found")
    table.insert(lines, "")
    table.insert(lines, "Tap to refresh")
  else
    local shown = 0
    for i, item in ipairs(state.items) do
      if shown >= CONFIG.max_items then
        table.insert(lines, string.format("   ... +%d more", #state.items - shown))
        break
      end

      local num = string.format("%d.", i)
      local title = truncate(item.title, 32)
      table.insert(lines, num .. " " .. title)
      shown = shown + 1
    end
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

  -- Footer with feed info
  local feed_num = CONFIG.current_feed .. "/" .. #FEEDS
  table.insert(lines, "📊 " .. #state.items .. " items | Feed " .. feed_num)

  ui:show_text(table.concat(lines, "\n"))
end

-- Fetch feed
local function fetch_feed()
  local feed = FEEDS[CONFIG.current_feed]
  if not feed then
    state.error = "Invalid feed"
    render()
    return
  end

  state.loading = true
  state.error = nil
  state.feed_name = feed.name
  render()

  http:get(feed.url, function(body, code)
    state.loading = false

    if code == 200 and body then
      local items = parse_feed(body)
      if #items > 0 then
        state.items = items
        state.last_refresh = os.time()
        save_data()
      else
        state.error = "No items parsed"
      end
    else
      state.error = "Failed to fetch (code: " .. tostring(code) .. ")"
    end

    render()
  end)
end

-- Callbacks
function on_resume()
  local saved = load_data()
  CONFIG.current_feed = saved.current_feed or 1
  state.items = saved.items or {}
  state.last_refresh = saved.last_refresh or 0

  -- Check if refresh needed
  local elapsed = os.time() - state.last_refresh
  if elapsed > CONFIG.refresh_minutes * 60 or #state.items == 0 then
    fetch_feed()
  else
    render()
  end
end

function on_click()
  if state.error then
    fetch_feed()
  elseif #state.items > 0 then
    -- Show item selection menu
    local menu = {}
    for i, item in ipairs(state.items) do
      if i > 10 then break end
      table.insert(menu, truncate(item.title, 35))
    end
    ui:show_context_menu(menu)
  else
    fetch_feed()
  end
end

function on_long_click()
  local menu = {
    "🔄 Refresh Feed",
    "━━━━━━━━━━━━━━━━"
  }

  -- Add feed options
  for i, feed in ipairs(FEEDS) do
    local check = i == CONFIG.current_feed and "✅ " or "⬜ "
    table.insert(menu, check .. feed.icon .. " " .. feed.name)
  end

  table.insert(menu, "━━━━━━━━━━━━━━━━")
  table.insert(menu, "⚙️ Settings")

  ui:show_context_menu(menu)
end

function on_context_menu_click(index)
  -- From on_click (item selection)
  if index <= #state.items then
    local item = state.items[index]
    if item and item.link and item.link ~= "" then
      system:open_browser(item.link)
    else
      -- Show description if no link
      local desc = item.description or "No description"
      ui:show_text(item.title .. "\n\n" .. truncate(desc, 200))
    end
    return
  end

  -- From on_long_click menu
  if index == 1 then
    fetch_feed()
  elseif index >= 3 and index <= 2 + #FEEDS then
    -- Switch feed
    CONFIG.current_feed = index - 2
    save_data()
    fetch_feed()
  elseif index == 3 + #FEEDS then
    -- Settings
    local settings = "⚙️ RSS Reader Settings\n\n"
    settings = settings .. "Max Items: " .. CONFIG.max_items .. "\n"
    settings = settings .. "Refresh: " .. CONFIG.refresh_minutes .. " min\n\n"
    settings = settings .. "━━━━━━━━━━━━━━━━\n"
    settings = settings .. "Configured Feeds:\n"
    for i, feed in ipairs(FEEDS) do
      settings = settings .. i .. ". " .. feed.icon .. " " .. feed.name .. "\n"
    end
    settings = settings .. "\nEdit widget code to add feeds"
    ui:show_text(settings)
  end
end

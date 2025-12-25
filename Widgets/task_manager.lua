-- Task Manager Widget for AIO Launcher
-- Todo list with priorities, due dates, and categories
-- Uses: storage, ui:show_text(), ui:show_buttons()

-- Configuration
local STORAGE_KEY = "task_manager_data"
local MAX_TASKS = 50

-- Priority levels
local PRIORITIES = {
  { id = "high", name = "High", icon = "🔴", color = "#FF5555" },
  { id = "medium", name = "Medium", icon = "🟡", color = "#FFAA00" },
  { id = "low", name = "Low", icon = "🟢", color = "#55FF55" }
}

-- Categories
local CATEGORIES = {
  { id = "work", name = "Work", icon = "💼" },
  { id = "personal", name = "Personal", icon = "👤" },
  { id = "shopping", name = "Shopping", icon = "🛒" },
  { id = "health", name = "Health", icon = "❤️" },
  { id = "other", name = "Other", icon = "📋" }
}

-- State
local tasks = {}
local filter = "all"  -- all, pending, completed, high, medium, low
local sort_by = "priority"  -- priority, date, category
local view_mode = "list"  -- list, stats

-- Helper functions
local function load_data()
  local data = storage:get(STORAGE_KEY)
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return { tasks = {}, filter = "all", sort_by = "priority" }
end

local function save_data()
  storage:put(STORAGE_KEY, json.encode({
    tasks = tasks,
    filter = filter,
    sort_by = sort_by
  }))
end

local function get_today()
  return os.date("%Y-%m-%d")
end

local function truncate(str, len)
  if not str then return "" end
  if #str <= len then return str end
  return str:sub(1, len - 2) .. ".."
end

local function get_priority_icon(priority)
  for _, p in ipairs(PRIORITIES) do
    if p.id == priority then return p.icon end
  end
  return "⚪"
end

local function get_priority_order(priority)
  if priority == "high" then return 1
  elseif priority == "medium" then return 2
  else return 3 end
end

local function get_category_icon(category)
  for _, c in ipairs(CATEGORIES) do
    if c.id == category then return c.icon end
  end
  return "📋"
end

local function is_overdue(due_date)
  if not due_date or due_date == "" then return false end
  return due_date < get_today()
end

local function format_due_date(due_date)
  if not due_date or due_date == "" then return "" end
  local today = get_today()
  if due_date == today then
    return "Today"
  elseif due_date < today then
    return "Overdue!"
  else
    -- Calculate days until
    local y, m, d = due_date:match("(%d+)-(%d+)-(%d+)")
    local ty, tm, td = today:match("(%d+)-(%d+)-(%d+)")
    if y and ty then
      local due_time = os.time({ year = y, month = m, day = d })
      local today_time = os.time({ year = ty, month = tm, day = td })
      local diff = math.floor((due_time - today_time) / 86400)
      if diff == 1 then return "Tomorrow"
      elseif diff <= 7 then return diff .. " days"
      else return due_date end
    end
  end
  return due_date
end

-- Filter and sort tasks
local function get_filtered_tasks()
  local filtered = {}

  for _, task in ipairs(tasks) do
    local include = true

    if filter == "pending" and task.completed then
      include = false
    elseif filter == "completed" and not task.completed then
      include = false
    elseif filter == "high" and task.priority ~= "high" then
      include = false
    elseif filter == "medium" and task.priority ~= "medium" then
      include = false
    elseif filter == "low" and task.priority ~= "low" then
      include = false
    elseif filter == "overdue" and (task.completed or not is_overdue(task.due_date)) then
      include = false
    end

    if include then
      table.insert(filtered, task)
    end
  end

  -- Sort
  table.sort(filtered, function(a, b)
    -- Completed tasks go to bottom
    if a.completed ~= b.completed then
      return not a.completed
    end

    if sort_by == "priority" then
      local pa = get_priority_order(a.priority)
      local pb = get_priority_order(b.priority)
      if pa ~= pb then return pa < pb end
      return (a.created or "") > (b.created or "")
    elseif sort_by == "date" then
      local da = a.due_date or "9999-99-99"
      local db = b.due_date or "9999-99-99"
      return da < db
    elseif sort_by == "category" then
      return (a.category or "") < (b.category or "")
    end
    return false
  end)

  return filtered
end

-- Get statistics
local function get_stats()
  local stats = {
    total = #tasks,
    pending = 0,
    completed = 0,
    overdue = 0,
    high = 0,
    medium = 0,
    low = 0
  }

  for _, task in ipairs(tasks) do
    if task.completed then
      stats.completed = stats.completed + 1
    else
      stats.pending = stats.pending + 1
      if is_overdue(task.due_date) then
        stats.overdue = stats.overdue + 1
      end
    end

    if task.priority == "high" then stats.high = stats.high + 1
    elseif task.priority == "medium" then stats.medium = stats.medium + 1
    else stats.low = stats.low + 1 end
  end

  return stats
end

-- Display functions
local function render()
  local lines = {}

  if view_mode == "stats" then
    -- Statistics view
    local stats = get_stats()

    table.insert(lines, "📊 Task Statistics")
    table.insert(lines, "")
    table.insert(lines, "📋 Total: " .. stats.total .. " tasks")
    table.insert(lines, "")
    table.insert(lines, "⏳ Pending: " .. stats.pending)
    table.insert(lines, "✅ Completed: " .. stats.completed)
    table.insert(lines, "⚠️ Overdue: " .. stats.overdue)
    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")
    table.insert(lines, "🔴 High: " .. stats.high)
    table.insert(lines, "🟡 Medium: " .. stats.medium)
    table.insert(lines, "🟢 Low: " .. stats.low)

    if stats.total > 0 then
      local completion = math.floor((stats.completed / stats.total) * 100)
      table.insert(lines, "")
      table.insert(lines, "📈 Completion: " .. completion .. "%")
    end

  else
    -- List view
    table.insert(lines, "📋 Task Manager")

    -- Filter indicator
    local filter_name = filter == "all" and "All" or filter:gsub("^%l", string.upper)
    table.insert(lines, "🔍 " .. filter_name .. " | Sort: " .. sort_by)
    table.insert(lines, "")

    local filtered = get_filtered_tasks()

    if #filtered == 0 then
      if #tasks == 0 then
        table.insert(lines, "No tasks yet!")
        table.insert(lines, "")
        table.insert(lines, "Long press to add a task")
      else
        table.insert(lines, "No tasks match filter")
      end
    else
      local shown = 0
      for i, task in ipairs(filtered) do
        if shown >= 8 then
          table.insert(lines, string.format("   ... +%d more", #filtered - shown))
          break
        end

        local check = task.completed and "✅" or "⬜"
        local priority = get_priority_icon(task.priority)
        local title = truncate(task.title, 20)

        local line = check .. " " .. priority .. " " .. title

        -- Add due date indicator
        if task.due_date and task.due_date ~= "" and not task.completed then
          if is_overdue(task.due_date) then
            line = line .. " ⚠️"
          elseif task.due_date == get_today() then
            line = line .. " 📅"
          end
        end

        table.insert(lines, line)
        shown = shown + 1
      end
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

    local stats = get_stats()
    table.insert(lines, string.format("✅ %d/%d done", stats.completed, stats.total))
    if stats.overdue > 0 then
      table.insert(lines, "⚠️ " .. stats.overdue .. " overdue")
    end
  end

  ui:show_text(table.concat(lines, "\n"))
end

-- Add a new task
local function add_task(title, priority, category, due_date)
  if not title or title == "" then return end

  local task = {
    id = tostring(os.time()) .. tostring(math.random(1000, 9999)),
    title = title,
    priority = priority or "medium",
    category = category or "other",
    due_date = due_date or "",
    completed = false,
    created = os.date("%Y-%m-%d %H:%M")
  }

  table.insert(tasks, 1, task)

  -- Limit total tasks
  while #tasks > MAX_TASKS do
    table.remove(tasks)
  end

  save_data()
  system:toast("Task added!")
  render()
end

-- Toggle task completion
local function toggle_task(task_id)
  for _, task in ipairs(tasks) do
    if task.id == task_id then
      task.completed = not task.completed
      if task.completed then
        task.completed_date = os.date("%Y-%m-%d %H:%M")
      else
        task.completed_date = nil
      end
      save_data()
      system:toast(task.completed and "Task completed!" or "Task reopened")
      render()
      return
    end
  end
end

-- Delete task
local function delete_task(task_id)
  for i, task in ipairs(tasks) do
    if task.id == task_id then
      table.remove(tasks, i)
      save_data()
      system:toast("Task deleted")
      render()
      return
    end
  end
end

-- Callbacks
function on_resume()
  local saved = load_data()
  tasks = saved.tasks or {}
  filter = saved.filter or "all"
  sort_by = saved.sort_by or "priority"
  render()
end

function on_click()
  if view_mode == "stats" then
    view_mode = "list"
    render()
    return
  end

  -- Show task selection menu for toggling
  local filtered = get_filtered_tasks()
  if #filtered == 0 then
    system:toast("No tasks to toggle")
    return
  end

  local menu = {}
  for i, task in ipairs(filtered) do
    if i > 10 then break end
    local check = task.completed and "✅" or "⬜"
    local priority = get_priority_icon(task.priority)
    table.insert(menu, check .. " " .. priority .. " " .. truncate(task.title, 25))
  end

  ui:show_context_menu(menu)
end

function on_long_click()
  ui:show_context_menu({
    "➕ Add Task",
    "━━━━━━━━━━━━━━━━",
    "📋 View All",
    "⏳ View Pending",
    "✅ View Completed",
    "⚠️ View Overdue",
    "━━━━━━━━━━━━━━━━",
    "🔴 Filter High Priority",
    "🟡 Filter Medium Priority",
    "🟢 Filter Low Priority",
    "━━━━━━━━━━━━━━━━",
    "📊 Sort by Priority",
    "📅 Sort by Due Date",
    "📁 Sort by Category",
    "━━━━━━━━━━━━━━━━",
    "📈 Show Statistics",
    "🗑️ Clear Completed",
    "⚙️ Settings"
  })
end

-- Track menu source
local menu_source = "long_click"
local filtered_for_click = {}

function on_context_menu_click(index)
  -- From on_click (task toggle menu)
  if menu_source == "click" then
    local task = filtered_for_click[index]
    if task then
      toggle_task(task.id)
    end
    menu_source = "long_click"
    return
  end

  -- From on_long_click menu
  if index == 1 then
    -- Add task - use clipboard as input
    local clipboard = system:clipboard()
    if clipboard and clipboard ~= "" and #clipboard < 100 then
      add_task(clipboard, "medium", "other", "")
    else
      system:toast("Copy task title to clipboard, then try again")
    end
  elseif index == 3 then
    filter = "all"
    save_data()
    render()
  elseif index == 4 then
    filter = "pending"
    save_data()
    render()
  elseif index == 5 then
    filter = "completed"
    save_data()
    render()
  elseif index == 6 then
    filter = "overdue"
    save_data()
    render()
  elseif index == 8 then
    filter = "high"
    save_data()
    render()
  elseif index == 9 then
    filter = "medium"
    save_data()
    render()
  elseif index == 10 then
    filter = "low"
    save_data()
    render()
  elseif index == 12 then
    sort_by = "priority"
    save_data()
    render()
  elseif index == 13 then
    sort_by = "date"
    save_data()
    render()
  elseif index == 14 then
    sort_by = "category"
    save_data()
    render()
  elseif index == 16 then
    view_mode = "stats"
    render()
  elseif index == 17 then
    -- Clear completed
    local new_tasks = {}
    local cleared = 0
    for _, task in ipairs(tasks) do
      if not task.completed then
        table.insert(new_tasks, task)
      else
        cleared = cleared + 1
      end
    end
    tasks = new_tasks
    save_data()
    system:toast("Cleared " .. cleared .. " completed tasks")
    render()
  elseif index == 18 then
    -- Settings
    local settings = "⚙️ Task Manager Settings\n\n"
    settings = settings .. "Max Tasks: " .. MAX_TASKS .. "\n"
    settings = settings .. "Current Filter: " .. filter .. "\n"
    settings = settings .. "Sort By: " .. sort_by .. "\n\n"
    settings = settings .. "━━━━━━━━━━━━━━━━\n"
    settings = settings .. "Adding Tasks:\n"
    settings = settings .. "1. Copy task title\n"
    settings = settings .. "2. Long press → Add Task\n\n"
    settings = settings .. "Priorities: 🔴 High 🟡 Med 🟢 Low"
    ui:show_text(settings)
  end
end

-- Override on_click to track menu source
local original_on_click = on_click
on_click = function()
  menu_source = "click"
  filtered_for_click = get_filtered_tasks()
  original_on_click()
end

-- GitHub Activity Widget for AIO Launcher
-- Public repo stats and commit activity (no auth required)
-- Uses: http:get(), storage, ui:show_chart()

-- Configuration - Set your GitHub username and optional repo
local GITHUB_USER = "anthropics"  -- Change to your username
local GITHUB_REPO = nil  -- Set to repo name for specific repo, or nil for user overview

local API_BASE = "https://api.github.com"
local STORAGE_KEY = "github_stats"

-- State
local user_data = nil
local repo_data = nil
local commits_data = nil
local commit_activity = {}
local pending_requests = 0

-- Helper functions
local function load_cache()
    local data = storage:get(STORAGE_KEY)
    if data then
        return json.decode(data)
    end
    return nil
end

local function save_cache(data)
    storage:put(STORAGE_KEY, json.encode(data))
end

local function format_number(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(num)
    end
end

local function time_ago(date_str)
    -- Simple relative time (GitHub dates are ISO 8601)
    -- This is approximate since we don't have full date parsing
    if not date_str then return "unknown" end

    -- Just show the date part for simplicity
    local date_part = date_str:match("^(%d+%-%d+%-%d+)")
    return date_part or date_str
end

-- Display functions
local function show_loading()
    ui:show_text("⏳ Loading GitHub data...")
end

local function show_user_overview()
    if not user_data then
        ui:show_text("❌ Failed to load GitHub data")
        return
    end

    local lines = {
        "🐙 GitHub: @" .. GITHUB_USER,
        ""
    }

    -- User stats
    if user_data.name then
        table.insert(lines, "👤 " .. user_data.name)
    end

    table.insert(lines, "")
    table.insert(lines, "📊 Stats:")
    table.insert(lines, "   📦 Repos: " .. format_number(user_data.public_repos or 0))
    table.insert(lines, "   👥 Followers: " .. format_number(user_data.followers or 0))
    table.insert(lines, "   👤 Following: " .. format_number(user_data.following or 0))

    if user_data.public_gists and user_data.public_gists > 0 then
        table.insert(lines, "   📝 Gists: " .. format_number(user_data.public_gists))
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

    if user_data.created_at then
        local joined = time_ago(user_data.created_at)
        table.insert(lines, "📅 Joined: " .. joined)
    end

    ui:show_text(table.concat(lines, "\n"))

    -- Show commit activity chart if available
    if #commit_activity >= 3 then
        ui:show_chart(commit_activity, nil, "Weekly Commits", true)
    end
end

local function show_repo_details()
    if not repo_data then
        show_user_overview()
        return
    end

    local lines = {
        "🐙 " .. GITHUB_USER .. "/" .. GITHUB_REPO,
        ""
    }

    -- Repo stats
    table.insert(lines, "📊 Stats:")
    table.insert(lines, "   ⭐ Stars: " .. format_number(repo_data.stargazers_count or 0))
    table.insert(lines, "   🍴 Forks: " .. format_number(repo_data.forks_count or 0))
    table.insert(lines, "   👀 Watchers: " .. format_number(repo_data.watchers_count or 0))
    table.insert(lines, "   ❗ Issues: " .. format_number(repo_data.open_issues_count or 0))

    table.insert(lines, "")

    -- Language
    if repo_data.language then
        table.insert(lines, "💻 Language: " .. repo_data.language)
    end

    -- Description
    if repo_data.description then
        table.insert(lines, "")
        local desc = repo_data.description
        if #desc > 50 then
            desc = desc:sub(1, 47) .. "..."
        end
        table.insert(lines, "📝 " .. desc)
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

    if repo_data.pushed_at then
        table.insert(lines, "🕐 Last push: " .. time_ago(repo_data.pushed_at))
    end

    ui:show_text(table.concat(lines, "\n"))

    -- Show commit activity chart
    if #commit_activity >= 3 then
        ui:show_chart(commit_activity, nil, "Commit Activity", true)
    end
end

-- Fetch commit activity (for chart)
local function fetch_commit_activity()
    local url
    if GITHUB_REPO then
        url = API_BASE .. "/repos/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/stats/participation"
    else
        -- For user overview, get events and count commits
        url = API_BASE .. "/users/" .. GITHUB_USER .. "/events/public"
    end

    http:get(url, function(body, code)
        pending_requests = pending_requests - 1

        if code == 200 and body then
            local data = json.decode(body)
            if data then
                if GITHUB_REPO and data.all then
                    -- Repo participation stats (last 52 weeks)
                    -- Take last 7 weeks for chart
                    commit_activity = {}
                    local start = math.max(1, #data.all - 6)
                    for i = start, #data.all do
                        table.insert(commit_activity, data.all[i] or 0)
                    end
                elseif type(data) == "table" and #data > 0 then
                    -- Count push events per day (last 7 entries)
                    commit_activity = {}
                    local push_count = 0
                    for i = 1, math.min(7, #data) do
                        if data[i].type == "PushEvent" then
                            push_count = push_count + 1
                        end
                        table.insert(commit_activity, push_count)
                    end
                end
            end
        end

        if pending_requests <= 0 then
            if GITHUB_REPO then
                show_repo_details()
            else
                show_user_overview()
            end
        end
    end)
end

-- Fetch repo data
local function fetch_repo()
    if not GITHUB_REPO then
        pending_requests = pending_requests - 1
        if pending_requests <= 0 then
            show_user_overview()
        end
        return
    end

    local url = API_BASE .. "/repos/" .. GITHUB_USER .. "/" .. GITHUB_REPO

    http:get(url, function(body, code)
        pending_requests = pending_requests - 1

        if code == 200 and body then
            repo_data = json.decode(body)
        end

        if pending_requests <= 0 then
            show_repo_details()
        end
    end)
end

-- Fetch user data
local function fetch_user()
    local url = API_BASE .. "/users/" .. GITHUB_USER

    http:get(url, function(body, code)
        pending_requests = pending_requests - 1

        if code == 200 and body then
            user_data = json.decode(body)
            -- Cache data
            save_cache({
                user = user_data,
                timestamp = os.time()
            })
        else
            -- Try to load from cache
            local cached = load_cache()
            if cached and cached.user then
                user_data = cached.user
            end
        end

        if pending_requests <= 0 then
            if GITHUB_REPO then
                show_repo_details()
            else
                show_user_overview()
            end
        end
    end)
end

-- Fetch all data
local function fetch_all()
    show_loading()

    pending_requests = 3
    user_data = nil
    repo_data = nil
    commit_activity = {}

    fetch_user()
    fetch_repo()
    fetch_commit_activity()
end

-- Callbacks
function on_resume()
    fetch_all()
end

function on_click()
    -- Open GitHub profile in browser
    local url = "https://github.com/" .. GITHUB_USER
    if GITHUB_REPO then
        url = url .. "/" .. GITHUB_REPO
    end
    system:open_browser(url)
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Refresh",
        "🌐 Open in Browser",
        "📋 Copy Profile URL"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        fetch_all()
    elseif index == 2 then
        local url = "https://github.com/" .. GITHUB_USER
        if GITHUB_REPO then
            url = url .. "/" .. GITHUB_REPO
        end
        system:open_browser(url)
    elseif index == 3 then
        local url = "https://github.com/" .. GITHUB_USER
        if GITHUB_REPO then
            url = url .. "/" .. GITHUB_REPO
        end
        system:copy_to_clipboard(url)
        system:toast("URL copied!")
    end
end

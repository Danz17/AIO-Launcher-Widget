-- AI Widget Generator for AIO Launcher
-- Generate new widgets using AI from descriptions
-- Uses: http:post(), storage, ui:show_text()

-- Configuration
local GROQ_API_KEY = ""  -- Set your Groq API key here or use storage
local STORAGE_KEY_API = "groq_api_key"
local STORAGE_KEY_HISTORY = "generator_history"

-- State
local current_description = ""
local generated_code = ""
local generation_history = {}
local is_generating = false

-- API reference for prompting
local API_REFERENCE = [[
AIO Launcher Widget API:
- ui:show_text(text) - Display text
- ui:show_lines(lines) - Display lines array
- ui:show_buttons(buttons, colors) - Display buttons
- ui:show_chart(points, format, title) - Show chart
- ui:show_progress_bar(text, value, max, color) - Progress bar
- ui:show_context_menu(items) - Context menu
- http:get(url, callback) - GET request
- http:post(url, body, callback) - POST request
- json.decode(str) - Parse JSON
- json.encode(table) - Stringify table
- storage:get(key) - Get stored value
- storage:put(key, value) - Store value
- Callbacks: on_resume(), on_click(), on_long_click()
]]

-- Helper functions
local function load_api_key()
    local stored = storage:get(STORAGE_KEY_API)
    if stored and stored ~= "" then
        return stored
    end
    return GROQ_API_KEY
end

local function save_api_key(key)
    storage:put(STORAGE_KEY_API, key)
end

local function load_history()
    local data = storage:get(STORAGE_KEY_HISTORY)
    if data then
        local decoded = json.decode(data)
        if decoded then
            return decoded
        end
    end
    return {}
end

local function save_history()
    local to_save = {}
    for i = 1, math.min(5, #generation_history) do
        table.insert(to_save, generation_history[i])
    end
    storage:put(STORAGE_KEY_HISTORY, json.encode(to_save))
end

local function add_to_history(desc, code)
    table.insert(generation_history, 1, {
        description = desc,
        code = code,
        timestamp = os.date("%Y-%m-%d %H:%M")
    })
    if #generation_history > 5 then
        table.remove(generation_history)
    end
    save_history()
end

-- Display functions
local function show_main()
    local lines = {
        "🤖 AI Widget Generator",
        "",
        "Generate AIO Launcher widgets using AI",
        "",
        "━━━━━━━━━━━━━━━━━━━━",
        ""
    }

    local api_key = load_api_key()
    if api_key and api_key ~= "" then
        table.insert(lines, "✅ API Key: Configured")
    else
        table.insert(lines, "⚠️ API Key: Not Set")
        table.insert(lines, "   Long press → Set API Key")
    end

    table.insert(lines, "")

    if #generation_history > 0 then
        table.insert(lines, "📜 Recent Generations:")
        for i, item in ipairs(generation_history) do
            local desc = item.description
            if #desc > 30 then
                desc = desc:sub(1, 27) .. "..."
            end
            table.insert(lines, "   " .. i .. ". " .. desc)
        end
    else
        table.insert(lines, "No widgets generated yet")
        table.insert(lines, "Tap to start generating!")
    end

    ui:show_text(table.concat(lines, "\n"))
end

local function show_generating()
    local lines = {
        "🤖 AI Widget Generator",
        "",
        "⏳ Generating widget...",
        "",
        "Description:",
        current_description,
        "",
        "Please wait..."
    }
    ui:show_text(table.concat(lines, "\n"))
end

local function show_result()
    if generated_code == "" then
        show_main()
        return
    end

    local preview = generated_code
    if #preview > 500 then
        preview = preview:sub(1, 497) .. "..."
    end

    local lines = {
        "🤖 Widget Generated!",
        "",
        "📝 Description:",
        current_description,
        "",
        "━━━━━━━━━━━━━━━━━━━━",
        "📋 Code Preview:",
        "",
        preview,
        "",
        "━━━━━━━━━━━━━━━━━━━━",
        "Long press → Copy full code"
    }
    ui:show_text(table.concat(lines, "\n"))
end

-- Generate widget via Groq API
local function generate_widget(description)
    local api_key = load_api_key()
    if not api_key or api_key == "" then
        system:toast("Please set API key first")
        return
    end

    current_description = description
    is_generating = true
    show_generating()

    local system_prompt = [[You are an expert AIO Launcher Lua widget developer.

]] .. API_REFERENCE .. [[

Create a complete, working widget based on the description.
Rules:
1. Use ONLY the APIs listed above
2. Use json.decode() NOT json:decode()
3. Handle nil/errors gracefully
4. Use emojis for visual appeal
5. Include all required callbacks

Output ONLY the Lua code, no explanations.]]

    local body = json.encode({
        model = "llama-3.3-70b-versatile",
        messages = {
            { role = "system", content = system_prompt },
            { role = "user", content = "Create widget: " .. description }
        },
        temperature = 0.5,
        max_tokens = 3000
    })

    local headers = {
        "Authorization: Bearer " .. api_key,
        "Content-Type: application/json"
    }

    http:post("https://api.groq.com/openai/v1/chat/completions", body, headers, function(response, code)
        is_generating = false

        if code == 200 and response then
            local data = json.decode(response)
            if data and data.choices and data.choices[1] then
                local content = data.choices[1].message.content or ""

                -- Extract code from markdown if present
                local lua_code = content:match("```lua\n(.-)\n```")
                if not lua_code then
                    lua_code = content:match("```\n(.-)\n```")
                end
                if not lua_code then
                    lua_code = content
                end

                generated_code = lua_code
                add_to_history(description, lua_code)
                system:toast("Widget generated!")
                show_result()
            else
                system:toast("Failed to parse response")
                show_main()
            end
        else
            system:toast("API Error: " .. (code or "unknown"))
            show_main()
        end
    end)
end

-- Input dialog for description
local function prompt_description()
    local examples = {
        "Battery monitor with graph",
        "Weather widget with forecast",
        "Countdown timer to date",
        "Random quote display",
        "System info dashboard"
    }

    ui:show_context_menu({
        "📝 Enter Description",
        "━━━━━━━━━━━━━━━",
        "💡 " .. examples[1],
        "💡 " .. examples[2],
        "💡 " .. examples[3],
        "💡 " .. examples[4],
        "💡 " .. examples[5]
    })
end

-- Callbacks
function on_resume()
    generation_history = load_history()
    if generated_code ~= "" then
        show_result()
    else
        show_main()
    end
end

function on_click()
    if is_generating then
        system:toast("Please wait...")
        return
    end
    prompt_description()
end

function on_long_click()
    ui:show_context_menu({
        "🔑 Set API Key",
        "📋 Copy Generated Code",
        "🔄 Generate New Widget",
        "🗑️ Clear History",
        "ℹ️ About"
    })
end

function on_context_menu_click(index)
    -- Main menu (from on_click)
    if index == 1 then
        -- Enter description - use clipboard
        system:toast("Type description and copy, then select example")
        return
    elseif index >= 3 and index <= 7 then
        -- Example descriptions
        local examples = {
            [3] = "A battery monitor widget showing level, charging status, temperature with a visual bar and history chart",
            [4] = "A weather widget that fetches current weather from wttr.in API and shows temperature, condition with icons",
            [5] = "A countdown timer widget to a specific date showing days, hours, minutes remaining with progress bar",
            [6] = "A random inspirational quote widget that fetches quotes from an API and displays with author name",
            [7] = "A system info dashboard showing battery, wifi signal, storage with visual indicators"
        }
        local desc = examples[index]
        if desc then
            generate_widget(desc)
        end
        return
    end

    -- Long click menu
    if index == 1 then
        -- Set API Key
        local clipboard = system:clipboard()
        if clipboard and clipboard:match("^gsk_") then
            save_api_key(clipboard)
            system:toast("API Key saved from clipboard!")
        else
            system:toast("Copy your Groq API key (gsk_...) then try again")
        end
    elseif index == 2 then
        -- Copy generated code
        if generated_code ~= "" then
            system:copy_to_clipboard(generated_code)
            system:toast("Code copied to clipboard!")
        else
            system:toast("No code to copy")
        end
    elseif index == 3 then
        -- Generate new
        generated_code = ""
        prompt_description()
    elseif index == 4 then
        -- Clear history
        generation_history = {}
        save_history()
        generated_code = ""
        system:toast("History cleared")
        show_main()
    elseif index == 5 then
        -- About
        local about = "🤖 AI Widget Generator\n\n"
        about = about .. "Generate AIO Launcher widgets\n"
        about = about .. "using Groq's LLaMA 3.3 AI model.\n\n"
        about = about .. "Get free API key at:\n"
        about = about .. "console.groq.com\n\n"
        about = about .. "Created with AIO Widget Emulator"
        ui:show_text(about)
    end
end

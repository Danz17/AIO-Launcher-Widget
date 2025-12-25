-- Forex/Currency Rates Widget for AIO Launcher
-- Real-time exchange rates with historical trend chart
-- Uses: http:get(), storage, ui:show_chart()

-- Configuration
local BASE_CURRENCY = "USD"
local TARGET_CURRENCIES = { "EUR", "GBP", "JPY", "CAD", "AUD" }
local MAX_HISTORY = 24
local STORAGE_KEY = "forex_history"

-- Free API (no key required, limited requests)
local API_URL = "https://api.exchangerate-api.com/v4/latest/" .. BASE_CURRENCY

-- State
local rates = {}
local rate_history = {}
local last_update = nil

-- Currency symbols
local CURRENCY_SYMBOLS = {
    USD = "$",
    EUR = "€",
    GBP = "£",
    JPY = "¥",
    CAD = "C$",
    AUD = "A$",
    CHF = "Fr",
    CNY = "¥",
    INR = "₹",
    MXN = "$",
    BRL = "R$",
    KRW = "₩"
}

local CURRENCY_FLAGS = {
    USD = "🇺🇸",
    EUR = "🇪🇺",
    GBP = "🇬🇧",
    JPY = "🇯🇵",
    CAD = "🇨🇦",
    AUD = "🇦🇺",
    CHF = "🇨🇭",
    CNY = "🇨🇳",
    INR = "🇮🇳",
    MXN = "🇲🇽",
    BRL = "🇧🇷",
    KRW = "🇰🇷"
}

-- Helper functions
local function load_history()
    local data = storage:get(STORAGE_KEY)
    if data then
        local decoded = json.decode(data)
        if decoded then
            return decoded
        end
    end
    return {}
end

local function save_history(history)
    storage:put(STORAGE_KEY, json.encode(history))
end

local function add_rate_point(currency, rate)
    if not rate_history[currency] then
        rate_history[currency] = {}
    end
    table.insert(rate_history[currency], rate)
    if #rate_history[currency] > MAX_HISTORY then
        table.remove(rate_history[currency], 1)
    end
end

local function get_change(currency)
    local history = rate_history[currency]
    if not history or #history < 2 then
        return 0, "→"
    end
    local current = history[#history]
    local previous = history[#history - 1]
    local change = ((current - previous) / previous) * 100

    local icon = "→"
    if change > 0.1 then
        icon = "↑"
    elseif change < -0.1 then
        icon = "↓"
    end

    return change, icon
end

local function format_rate(rate, currency)
    if currency == "JPY" or currency == "KRW" then
        return string.format("%.2f", rate)
    else
        return string.format("%.4f", rate)
    end
end

local function get_symbol(currency)
    return CURRENCY_SYMBOLS[currency] or currency
end

local function get_flag(currency)
    return CURRENCY_FLAGS[currency] or "💱"
end

-- Display rates
local function show_rates()
    if not rates or not next(rates) then
        ui:show_text("⏳ Loading exchange rates...")
        return
    end

    local lines = {
        "💱 Exchange Rates",
        "Base: " .. get_flag(BASE_CURRENCY) .. " " .. BASE_CURRENCY,
        ""
    }

    for _, currency in ipairs(TARGET_CURRENCIES) do
        local rate = rates[currency]
        if rate then
            local change, icon = get_change(currency)
            local change_str = string.format("%+.2f%%", change)
            local color_icon = change > 0 and "🟢" or (change < 0 and "🔴" or "⚪")

            table.insert(lines, get_flag(currency) .. " " .. currency .. "/" .. BASE_CURRENCY)
            table.insert(lines, "   " .. get_symbol(currency) .. " " .. format_rate(rate, currency) .. " " .. icon .. " " .. change_str)
        end
    end

    table.insert(lines, "")
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")

    if last_update then
        table.insert(lines, "🕐 Updated: " .. last_update)
    end

    ui:show_text(table.concat(lines, "\n"))

    -- Show chart for first currency with history
    for _, currency in ipairs(TARGET_CURRENCIES) do
        local history = rate_history[currency]
        if history and #history >= 3 then
            -- Scale values for better chart visibility
            local scaled = {}
            local min_val = math.min(table.unpack(history))
            for _, v in ipairs(history) do
                -- Normalize to percentage change from min
                table.insert(scaled, (v / min_val) * 100)
            end
            ui:show_chart(scaled, nil, currency .. "/" .. BASE_CURRENCY .. " Trend", true)
            break
        end
    end
end

-- Fetch rates from API
local function fetch_rates()
    ui:show_text("⏳ Fetching exchange rates...")

    http:get(API_URL, function(body, code)
        if code == 200 and body then
            local data = json.decode(body)
            if data and data.rates then
                rates = data.rates

                -- Update history for each target currency
                for _, currency in ipairs(TARGET_CURRENCIES) do
                    if rates[currency] then
                        add_rate_point(currency, rates[currency])
                    end
                end

                -- Update timestamp
                last_update = os.date("%H:%M")

                -- Save history
                save_history(rate_history)

                show_rates()
            else
                ui:show_text("❌ Failed to parse rates data")
            end
        else
            ui:show_text("❌ Failed to fetch rates\nCode: " .. (code or "N/A"))
        end
    end)
end

-- Callbacks
function on_resume()
    rate_history = load_history()
    fetch_rates()
end

function on_click()
    fetch_rates()
end

function on_long_click()
    ui:show_context_menu({
        "🔄 Refresh Rates",
        "📊 Show All Charts",
        "💱 Quick Convert",
        "🗑️ Clear History"
    })
end

function on_context_menu_click(index)
    if index == 1 then
        fetch_rates()
    elseif index == 2 then
        -- Show detailed stats
        local lines = { "📊 Rate History", "" }
        for _, currency in ipairs(TARGET_CURRENCIES) do
            local history = rate_history[currency]
            if history and #history > 0 then
                local min_val = math.min(table.unpack(history))
                local max_val = math.max(table.unpack(history))
                local current = history[#history]
                table.insert(lines, get_flag(currency) .. " " .. currency)
                table.insert(lines, "   Current: " .. format_rate(current, currency))
                table.insert(lines, "   Range: " .. format_rate(min_val, currency) .. " - " .. format_rate(max_val, currency))
                table.insert(lines, "   Samples: " .. #history)
                table.insert(lines, "")
            end
        end
        ui:show_text(table.concat(lines, "\n"))
    elseif index == 3 then
        -- Quick convert 100 USD
        if rates and next(rates) then
            local lines = { "💱 100 " .. BASE_CURRENCY .. " =", "" }
            for _, currency in ipairs(TARGET_CURRENCIES) do
                if rates[currency] then
                    local converted = 100 * rates[currency]
                    table.insert(lines, get_flag(currency) .. " " .. string.format("%.2f", converted) .. " " .. currency)
                end
            end
            ui:show_text(table.concat(lines, "\n"))
        end
    elseif index == 4 then
        rate_history = {}
        save_history(rate_history)
        system:toast("History cleared")
        fetch_rates()
    end
end

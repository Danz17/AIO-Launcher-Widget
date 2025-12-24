-- name = "MikroTik Debug"
-- description = "Debug HTTP auth methods for MikroTik"
-- type = "widget"

local CONFIG = {
  ip = "10.1.1.1",
  username = "admin",
  password = "admin123"
}

local state = {
  results = {},
  test_count = 0,
  done_count = 0
}

local function base64_encode(data)
  local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x)
    local r, b = '', x:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
    return r
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x < 6 then return '' end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
    return b:sub(c + 1, c + 1)
  end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function show_results()
  local o = "MikroTik HTTP Debug\n"
  o = o .. "IP: " .. CONFIG.ip .. "\n"
  o = o .. "━━━━━━━━━━━━━━━━━━━━━━\n\n"

  if state.done_count < state.test_count then
    o = o .. "Testing... " .. state.done_count .. "/" .. state.test_count .. "\n"
  else
    for name, result in pairs(state.results) do
      local status = ""
      if result.code == 200 then
        status = "SUCCESS"
      elseif result.code == 401 then
        status = "AUTH FAIL"
      elseif result.code == 0 then
        status = "NO RESPONSE"
      else
        status = "HTTP " .. result.code
      end
      o = o .. name .. ": " .. status .. "\n"
      if result.error then
        o = o .. "  Error: " .. result.error .. "\n"
      end
      if result.body and #result.body > 0 then
        o = o .. "  Body: " .. result.body:sub(1, 50) .. "\n"
      end
      o = o .. "\n"
    end
  end

  o = o .. "\nTap to run tests again"
  ui:show_text(o)
end

local function check_done()
  state.done_count = state.done_count + 1
  show_results()
end

-- Test 1: No auth (expect 401)
function on_network_result_noauth(body, code)
  state.results["1. No Auth"] = { code = code, body = body or "" }
  check_done()
end

function on_network_error_noauth(err)
  state.results["1. No Auth"] = { code = 0, error = tostring(err) }
  check_done()
end

-- Test 2: URL-embedded auth
function on_network_result_urlauth(body, code)
  state.results["2. URL Auth"] = { code = code, body = body or "" }
  check_done()
end

function on_network_error_urlauth(err)
  state.results["2. URL Auth"] = { code = 0, error = tostring(err) }
  check_done()
end

-- Test 3: Header auth
function on_network_result_headerauth(body, code)
  state.results["3. Header Auth"] = { code = code, body = body or "" }
  check_done()
end

function on_network_error_headerauth(err)
  state.results["3. Header Auth"] = { code = 0, error = tostring(err) }
  check_done()
end

function on_resume()
  state.results = {}
  state.test_count = 3
  state.done_count = 0

  ui:show_text("Running HTTP tests...\n\nPlease wait...")

  local endpoint = "/rest/system/resource"

  -- Test 1: No auth
  http:get("http://" .. CONFIG.ip .. endpoint, "noauth")

  -- Test 2: URL-embedded credentials
  http:get("http://" .. CONFIG.username .. ":" .. CONFIG.password .. "@" .. CONFIG.ip .. endpoint, "urlauth")

  -- Test 3: Authorization header
  local auth = base64_encode(CONFIG.username .. ":" .. CONFIG.password)
  http:set_headers({
    "Authorization: Basic " .. auth
  })
  http:get("http://" .. CONFIG.ip .. endpoint, "headerauth")
end

function on_click()
  on_resume()
end

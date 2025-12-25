#!/usr/bin/env node

// Web Server for Visual Emulator
import express from 'express';
import cors from 'cors';
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync, unlinkSync, mkdirSync, appendFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';
import { lua, lauxlib, lualib, to_luastring } from 'fengari';
import { ui, clearOutput, getOutputBuffer } from './api/ui.js';
import { http, loadMocks, setHttpMode, setHttpLogCallback } from './api/http.js';
import { json } from './api/json.js';
import { system } from './api/system.js';
import { android } from './api/android.js';
import { storage } from './api/storage.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());
app.use(express.static(join(__dirname, 'public')));

// Lua state per request (we'll create a new one for each execution)
let currentL = null;

// Initialize Lua state and APIs
function initLua() {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    
    // Create ui module
    lua.lua_createtable(L, 0, 2);
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_text, true));
    lua.lua_setfield(L, -2, to_luastring("show_text"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_context_menu, true));
    lua.lua_setfield(L, -2, to_luastring("show_context_menu"));
    lua.lua_setglobal(L, to_luastring("ui"));
    
    // Create http module
    lua.lua_createtable(L, 0, 2);
    lua.lua_pushcfunction(L, luaWrapFunction(http.get, true));
    lua.lua_setfield(L, -2, to_luastring("get"));
    lua.lua_pushcfunction(L, luaWrapFunction(http.post, true));
    lua.lua_setfield(L, -2, to_luastring("post"));
    lua.lua_setglobal(L, to_luastring("http"));
    
    // Create json module
    lua.lua_createtable(L, 0, 2);
    lua.lua_pushcfunction(L, luaWrapFunction(json.decode, true));
    lua.lua_setfield(L, -2, to_luastring("decode"));
    lua.lua_pushcfunction(L, luaWrapFunction(json.encode, true));
    lua.lua_setfield(L, -2, to_luastring("encode"));
    lua.lua_setglobal(L, to_luastring("json"));
    
    // Create system module
    lua.lua_createtable(L, 0, 3);
    lua.lua_pushcfunction(L, luaWrapFunction(system.open_browser, true));
    lua.lua_setfield(L, -2, to_luastring("open_browser"));
    lua.lua_pushcfunction(L, luaWrapFunction(system.toast, true));
    lua.lua_setfield(L, -2, to_luastring("toast"));
    lua.lua_pushcfunction(L, luaWrapFunction(system.hmac_sha256, true));
    lua.lua_setfield(L, -2, to_luastring("hmac_sha256"));
    lua.lua_setglobal(L, to_luastring("system"));
    
    // Create android module
    lua.lua_createtable(L, 0, 20);
    for (const [key, value] of Object.entries(android)) {
        if (typeof value === 'function') {
            lua.lua_pushcfunction(L, luaWrapFunction(value, false));
            lua.lua_setfield(L, -2, to_luastring(key));
        }
    }
    lua.lua_setglobal(L, to_luastring("android"));
    
    return L;
}

// Wrap JavaScript function for Lua
function luaWrapFunction(fn, skipFirst = false) {
    return function(L) {
        const nargs = lua.lua_gettop(L);
        const args = [];
        const startIdx = skipFirst ? 2 : 1;
        
        for (let i = startIdx; i <= nargs; i++) {
            const type = lua.lua_type(L, i);
            if (type === lua.LUA_TSTRING) {
                const str = lua.lua_tojsstring(L, i);
                args.push(str !== null ? str : '');
            } else if (type === lua.LUA_TNUMBER) {
                args.push(lua.lua_tonumber(L, i));
            } else if (type === lua.LUA_TBOOLEAN) {
                args.push(lua.lua_toboolean(L, i));
            } else if (type === lua.LUA_TTABLE) {
                args.push(luaTableToJS(L, i));
            } else if (type === lua.LUA_TFUNCTION) {
                args.push(createLuaCallback(L, i));
            } else {
                args.push(null);
            }
        }
        
        try {
            const result = fn.apply(null, args);
            
            if (result !== undefined && result !== null) {
                if (typeof result === 'string') {
                    lua.lua_pushstring(L, to_luastring(result));
                } else if (typeof result === 'number') {
                    lua.lua_pushnumber(L, result);
                } else if (typeof result === 'boolean') {
                    lua.lua_pushboolean(L, result);
                } else if (typeof result === 'object') {
                    jsToLuaTable(L, result);
                } else {
                    lua.lua_pushnil(L);
                }
                return 1;
            }
        } catch (e) {
            console.error(`Error in ${fn.name}: ${e.message}`);
            lua.lua_pushnil(L);
            return 1;
        }
        
        return 0;
    };
}

// Create Lua callback function
function createLuaCallback(L, index) {
    lua.lua_pushvalue(L, index);
    const ref = lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX);
    
    return function(...args) {
        lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, ref);
        
        for (const arg of args) {
            if (typeof arg === 'string') {
                lua.lua_pushstring(L, to_luastring(arg));
            } else if (typeof arg === 'number') {
                lua.lua_pushnumber(L, arg);
            } else if (typeof arg === 'boolean') {
                lua.lua_pushboolean(L, arg);
            } else if (typeof arg === 'object' && arg !== null) {
                jsToLuaTable(L, arg);
            } else {
                lua.lua_pushnil(L);
            }
        }
        
        const result = lua.lua_pcall(L, args.length, 0, 0);
        if (result !== lua.LUA_OK) {
            const error = lua.lua_tojsstring(L, -1);
            console.error(`Lua callback error: ${error}`);
        }
    };
}

// Convert Lua table to JavaScript object
function luaTableToJS(L, index) {
    const obj = {};
    lua.lua_pushnil(L);
    while (lua.lua_next(L, index) !== 0) {
        const key = lua.lua_tojsstring(L, -2);
        const type = lua.lua_type(L, -1);
        let value;
        
        if (type === lua.LUA_TSTRING) {
            value = lua.lua_tojsstring(L, -1);
        } else if (type === lua.LUA_TNUMBER) {
            value = lua.lua_tonumber(L, -1);
        } else if (type === lua.LUA_TBOOLEAN) {
            value = lua.lua_toboolean(L, -1);
        } else if (type === lua.LUA_TTABLE) {
            value = luaTableToJS(L, -1);
        } else {
            value = null;
        }
        
        obj[key] = value;
        lua.lua_pop(L, 1);
    }
    return obj;
}

// Convert JavaScript object to Lua table
function jsToLuaTable(L, obj) {
    lua.lua_createtable(L, 0, Object.keys(obj).length);
    for (const [key, value] of Object.entries(obj)) {
        lua.lua_pushstring(L, to_luastring(key));
        if (typeof value === 'string') {
            lua.lua_pushstring(L, to_luastring(value));
        } else if (typeof value === 'number') {
            lua.lua_pushnumber(L, value);
        } else if (typeof value === 'boolean') {
            lua.lua_pushboolean(L, value);
        } else if (typeof value === 'object' && value !== null) {
            jsToLuaTable(L, value);
        } else {
            lua.lua_pushnil(L);
        }
        lua.lua_settable(L, -3);
    }
}

// Load and execute Lua script
function loadScript(L, script) {
    try {
        const status = lauxlib.luaL_loadstring(L, to_luastring(script));
        if (status !== lua.LUA_OK) {
            let error = 'Unknown error';
            if (lua.lua_type(L, -1) === lua.LUA_TSTRING) {
                error = lua.lua_tojsstring(L, -1) || error;
            }
            lua.lua_pop(L, 1);
            throw new Error(`Lua load error: ${error}`);
        }
        
        const result = lua.lua_pcall(L, 0, 0, 0);
        if (result !== lua.LUA_OK) {
            let error = 'Unknown error';
            if (lua.lua_type(L, -1) === lua.LUA_TSTRING) {
                error = lua.lua_tojsstring(L, -1) || error;
            }
            lua.lua_pop(L, 1);
            throw new Error(`Lua runtime error: ${error}`);
        }
        
        return true;
    } catch (e) {
        throw e;
    }
}

// Call Lua function
function callLuaFunction(L, name, ...args) {
    lua.lua_getglobal(L, to_luastring(name));
    if (lua.lua_isfunction(L, -1)) {
        for (const arg of args) {
            if (typeof arg === 'string') {
                lua.lua_pushstring(L, to_luastring(arg));
            } else if (typeof arg === 'number') {
                lua.lua_pushnumber(L, arg);
            } else if (typeof arg === 'boolean') {
                lua.lua_pushboolean(L, arg);
            } else {
                lua.lua_pushnil(L);
            }
        }
        
        const result = lua.lua_pcall(L, args.length, 0, 0);
        if (result !== lua.LUA_OK) {
            const error = lua.lua_tojsstring(L, -1);
            const errorObj = new Error(`Error calling ${name}: ${error}`);
            errorObj.luaError = error;
            errorObj.functionName = name;
            throw errorObj;
        }
        return true;
    } else {
        lua.lua_pop(L, 1);
        return false;
    }
}

// API Routes

// Execute Lua script
app.post('/api/execute', async (req, res) => {
    try {
        const { script, functionName, mockData } = req.body;
        
        // Clear previous output
        clearOutput();
        
        // Collect HTTP logs for this request
        const httpLogs = [];
        setHttpLogCallback((type, details) => {
            httpLogs.push({ type, ...details, timestamp: new Date().toISOString() });
        });
        
        // Load mocks if provided
        if (mockData) {
            // Store mock data temporarily
            const mockPath = join(__dirname, 'mocks', 'temp_mock.json');
            writeFileSync(mockPath, JSON.stringify(mockData, null, 2));
            loadMocks(mockPath);
        }
        
        // Initialize Lua state
        const L = initLua();
        currentL = L;
        
        // Load script (may throw)
        try {
            loadScript(L, script);
        } catch (loadError) {
            setHttpLogCallback(null);
            console.error('Lua load error:', loadError);
            return res.status(500).json({
                success: false,
                error: loadError.message,
                errorStack: loadError.stack,
                errorType: 'LUA_LOAD_ERROR'
            });
        }
        
        // Wait a bit for async operations
        await new Promise(resolve => setTimeout(resolve, 100));
        
        // Call function if specified, otherwise call on_resume
        const funcToCall = functionName || 'on_resume';
        let exists = false;
        try {
            exists = callLuaFunction(L, funcToCall);
        } catch (callError) {
            setHttpLogCallback(null);
            console.error('Lua runtime error:', callError);
            console.error('Lua error details:', {
                message: callError.message,
                luaError: callError.luaError,
                functionName: callError.functionName,
                stack: callError.stack
            });
            return res.status(500).json({
                success: false,
                error: callError.message,
                errorStack: callError.stack,
                errorType: 'LUA_RUNTIME_ERROR',
                luaError: callError.luaError,
                functionName: callError.functionName
            });
        }
        
        // Wait for async operations to complete
        await new Promise(resolve => setTimeout(resolve, 500));
        
        // Get output
        const output = getOutputBuffer();
        
        // Clear log callback
        setHttpLogCallback(null);
        
        res.json({
            success: true,
            output: output,
            functionExists: exists,
            httpLogs: httpLogs
        });
    } catch (error) {
        setHttpLogCallback(null);
        console.error('Unexpected error in /api/execute:', error);
        console.error('Error stack:', error.stack);
        res.status(500).json({
            success: false,
            error: error.message,
            errorStack: error.stack,
            errorType: 'UNEXPECTED_ERROR'
        });
    }
});

// Get available mock files
app.get('/api/mocks', (req, res) => {
    try {
        const mocksDir = join(__dirname, 'mocks');
        if (!existsSync(mocksDir)) {
            return res.json([]);
        }
        
        const files = readdirSync(mocksDir)
            .filter(f => f.endsWith('.json'))
            .map(f => ({
                name: f,
                path: join(mocksDir, f)
            }));
        
        res.json(files);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Load mock file
app.get('/api/mocks/:filename', (req, res) => {
    try {
        const filePath = join(__dirname, 'mocks', req.params.filename);
        if (!existsSync(filePath)) {
            return res.status(404).json({ error: 'Mock file not found' });
        }
        
        const content = readFileSync(filePath, 'utf8');
        res.json(JSON.parse(content));
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Save mock file
app.post('/api/mocks/:filename', (req, res) => {
    try {
        const filePath = join(__dirname, 'mocks', req.params.filename);
        writeFileSync(filePath, JSON.stringify(req.body, null, 2));
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get available widget scripts
app.get('/api/widgets', (req, res) => {
    try {
        const widgetsDir = resolve(__dirname, '..', 'Widgets');
        const mikrotikDir = resolve(__dirname, '..', 'Widgets', 'Mikrotik');
        const widgets = [];
        
        // Scan Widgets directory (only files, not directories)
        if (existsSync(widgetsDir)) {
            const files = readdirSync(widgetsDir)
                .filter(f => {
                    // Only include .lua files (not directories)
                    if (!f.endsWith('.lua')) return false;
                    try {
                        const fullPath = join(widgetsDir, f);
                        const stats = statSync(fullPath);
                        return stats.isFile(); // Only files, not directories
                    } catch {
                        return false;
                    }
                })
                .map(f => ({
                    name: f.replace('.lua', ''),
                    path: join(widgetsDir, f),
                    category: 'Widgets'
                }));
            widgets.push(...files);
        }
        
        // Scan Mikrotik directory (now inside Widgets folder)
        if (existsSync(mikrotikDir)) {
            const files = readdirSync(mikrotikDir)
                .filter(f => {
                    if (!f.endsWith('.lua')) return false;
                    try {
                        const fullPath = join(mikrotikDir, f);
                        const stats = statSync(fullPath);
                        return stats.isFile();
                    } catch {
                        return false;
                    }
                })
                .map(f => ({
                    name: 'MikroTik - ' + f.replace('.lua', ''),
                    path: join(mikrotikDir, f),
                    category: 'MikroTik'
                }));
            widgets.push(...files);
        }
        
        console.log(`Found ${widgets.length} widgets:`, widgets.map(w => w.name));
        res.json(widgets);
    } catch (error) {
        console.error('Error loading widgets:', error);
        res.status(500).json({ error: error.message });
    }
});

// Load widget script
app.get('/api/widgets/load', (req, res) => {
    try {
        const { path } = req.query;
        if (!path || !existsSync(path)) {
            return res.status(404).json({ error: 'Widget not found' });
        }

        const content = readFileSync(path, 'utf8');
        res.json({ content });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Upload/save widget script
app.post('/api/widgets/upload', (req, res) => {
    try {
        const { filename, content } = req.body;
        if (!filename || !content) {
            return res.status(400).json({ error: 'Missing filename or content' });
        }

        // Sanitize filename - only allow alphanumeric, underscore, hyphen
        const safeName = filename.replace(/[^a-zA-Z0-9_-]/g, '_');
        const widgetsDir = resolve(__dirname, '..', 'Widgets');
        const filePath = join(widgetsDir, `${safeName}.lua`);

        writeFileSync(filePath, content, 'utf8');
        console.log(`Widget saved: ${filePath}`);

        res.json({ success: true, path: filePath, name: safeName });
    } catch (error) {
        console.error('Error saving widget:', error);
        res.status(500).json({ error: error.message });
    }
});

// Delete widget script
app.delete('/api/widgets/:name', (req, res) => {
    try {
        const widgetName = req.params.name;
        const widgetsDir = resolve(__dirname, '..', 'Widgets');
        const mikrotikDir = resolve(__dirname, '..', 'Widgets', 'Mikrotik');

        // Check both directories
        let filePath = join(widgetsDir, `${widgetName}.lua`);
        if (!existsSync(filePath)) {
            filePath = join(mikrotikDir, `${widgetName}.lua`);
        }

        if (!existsSync(filePath)) {
            return res.status(404).json({ error: 'Widget not found' });
        }

        unlinkSync(filePath);
        console.log(`Widget deleted: ${filePath}`);

        res.json({ success: true });
    } catch (error) {
        console.error('Error deleting widget:', error);
        res.status(500).json({ error: error.message });
    }
});

// Set HTTP mode (mock/real)
let currentHttpMode = 'mock';
app.post('/api/http-mode', (req, res) => {
    try {
        const { mode } = req.body;
        if (mode === 'mock' || mode === 'real') {
            currentHttpMode = mode;
            setHttpMode(mode);  // Update http module
            res.json({ success: true, mode: currentHttpMode });
        } else {
            res.status(400).json({ error: 'Invalid mode' });
        }
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/http-mode', (req, res) => {
    res.json({ mode: currentHttpMode });
});

// Storage API endpoints
app.get('/api/storage', (req, res) => {
    try {
        const data = storage.getAll();
        res.json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.delete('/api/storage', (req, res) => {
    try {
        storage.clear();
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Settings storage
let currentSettings = {
    mikrotik: { ip: '10.1.1.1', user: 'admin', pass: '' },
    tuya: { clientId: '', secret: '' },
    crypto: { apiKey: '' },
    autoDelay: 1000
};

app.post('/api/settings', (req, res) => {
    try {
        currentSettings = { ...currentSettings, ...req.body };
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/settings', (req, res) => {
    res.json(currentSettings);
});

// MikroTik monitoring endpoints
app.get('/api/mikrotik/users', async (req, res) => {
    try {
        const { ip, user, pass } = req.query;
        const routerIp = ip || currentSettings.mikrotik.ip;
        const routerUser = user || currentSettings.mikrotik.user;
        const routerPass = pass || currentSettings.mikrotik.pass;

        const auth = Buffer.from(`${routerUser}:${routerPass}`).toString('base64');

        // Try hotspot active users first
        const hotspotResponse = await fetch(`http://${routerIp}/rest/ip/hotspot/active`, {
            headers: { 'Authorization': `Basic ${auth}` }
        });

        if (hotspotResponse.ok) {
            const hotspotUsers = await hotspotResponse.json();
            res.json({ type: 'hotspot', users: hotspotUsers });
            return;
        }

        // Try PPPoE active users
        const pppoeResponse = await fetch(`http://${routerIp}/rest/ppp/active`, {
            headers: { 'Authorization': `Basic ${auth}` }
        });

        if (pppoeResponse.ok) {
            const pppoeUsers = await pppoeResponse.json();
            res.json({ type: 'pppoe', users: pppoeUsers });
            return;
        }

        res.json({ type: 'none', users: [], error: 'No active users found' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/mikrotik/interfaces', async (req, res) => {
    try {
        const { ip, user, pass } = req.query;
        const routerIp = ip || currentSettings.mikrotik.ip;
        const routerUser = user || currentSettings.mikrotik.user;
        const routerPass = pass || currentSettings.mikrotik.pass;

        const auth = Buffer.from(`${routerUser}:${routerPass}`).toString('base64');

        const response = await fetch(`http://${routerIp}/rest/interface`, {
            headers: { 'Authorization': `Basic ${auth}` }
        });

        if (response.ok) {
            const interfaces = await response.json();
            res.json(interfaces);
        } else {
            res.status(response.status).json({ error: 'Failed to fetch interfaces' });
        }
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/mikrotik/traffic', async (req, res) => {
    try {
        const { ip, user, pass, iface } = req.query;
        const routerIp = ip || currentSettings.mikrotik.ip;
        const routerUser = user || currentSettings.mikrotik.user;
        const routerPass = pass || currentSettings.mikrotik.pass;
        const interfaceName = iface || 'ether1';

        const auth = Buffer.from(`${routerUser}:${routerPass}`).toString('base64');

        // Use interface monitor-traffic for real-time stats
        const response = await fetch(`http://${routerIp}/rest/interface/monitor-traffic`, {
            method: 'POST',
            headers: {
                'Authorization': `Basic ${auth}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                interface: interfaceName,
                once: true
            })
        });

        if (response.ok) {
            const traffic = await response.json();
            res.json(traffic);
        } else {
            // Fallback to interface stats
            const statsResponse = await fetch(`http://${routerIp}/rest/interface?name=${interfaceName}`, {
                headers: { 'Authorization': `Basic ${auth}` }
            });

            if (statsResponse.ok) {
                const stats = await statsResponse.json();
                res.json(stats[0] || {});
            } else {
                res.status(response.status).json({ error: 'Failed to fetch traffic' });
            }
        }
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ============================================================================
// AI Script Inspector
// ============================================================================

// Logging directory for AI analysis
const logsDir = resolve(__dirname, 'logs');
if (!existsSync(logsDir)) {
    mkdirSync(logsDir, { recursive: true });
}

function logInspectorAnalysis(originalScript, analysis, success = true) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const logFile = join(logsDir, `inspector-${timestamp}.json`);

    const logEntry = {
        timestamp: new Date().toISOString(),
        success,
        originalScript,
        analysis,
        scriptPreview: originalScript.substring(0, 200) + '...'
    };

    writeFileSync(logFile, JSON.stringify(logEntry, null, 2), 'utf8');
    console.log(`📝 Inspector log saved: ${logFile}`);

    // Also append to summary log
    const summaryFile = join(logsDir, 'inspector-summary.log');
    const summaryLine = `[${logEntry.timestamp}] ${success ? '✓' : '✗'} ${logEntry.scriptPreview.replace(/\n/g, ' ').substring(0, 80)}\n`;
    appendFileSync(summaryFile, summaryLine, 'utf8');
}

// STRICT API Reference - ONLY these functions exist in the emulator
const AIO_API_REFERENCE = `
═══════════════════════════════════════════════════════════════════════════════
                    AIO LAUNCHER WIDGET API - COMPLETE REFERENCE
                    ⚠️ ONLY USE FUNCTIONS LISTED BELOW - NO OTHERS EXIST ⚠️
═══════════════════════════════════════════════════════════════════════════════

📱 UI MODULE (ui:)
─────────────────────────────────────────────────────────────────────────────
✅ ui:show_text(text)              → Display simple text string
✅ ui:show_lines(lines_table)      → Display array of text lines
✅ ui:show_table(rows_table)       → Display table with rows
✅ ui:show_buttons(buttons, callback_name) → Display clickable buttons
✅ ui:show_progress(value, max)    → Show progress bar (0-100)
✅ ui:show_chart(data, options)    → Show chart visualization
✅ ui:set_folding_mark(text)       → Set folding marker text

❌ DOES NOT EXIST: ui:set_headers, ui:show_header, ui:add_row, ui:clear

🌐 HTTP MODULE (http:)
─────────────────────────────────────────────────────────────────────────────
✅ http:get(url, callback)         → GET request, callback receives (body, code)
✅ http:get(url, headers_table, callback) → GET with headers
✅ http:post(url, body, callback)  → POST request
✅ http:post(url, body, headers_table, callback) → POST with headers

Headers format: {["Authorization"] = "Basic xxx", ["Content-Type"] = "application/json"}

❌ DOES NOT EXIST: http:set_headers, http:request, http:put, http:delete, http:fetch

📦 JSON MODULE (json.)
─────────────────────────────────────────────────────────────────────────────
✅ json.decode(json_string)        → Parse JSON string to Lua table
✅ json.encode(lua_table)          → Convert Lua table to JSON string

❌ DOES NOT EXIST: json:decode, json:encode (use dot notation, not colon!)

💾 STORAGE MODULE (storage:)
─────────────────────────────────────────────────────────────────────────────
✅ storage:get(key)                → Get stored value (returns nil if not found)
✅ storage:put(key, value)         → Store a value
✅ storage:delete(key)             → Delete a stored value

❌ DOES NOT EXIST: storage:set, storage:save, storage:load, storage:clear

🔧 SYSTEM MODULE (system:)
─────────────────────────────────────────────────────────────────────────────
✅ system:toast(message)           → Show toast notification
✅ system:open_browser(url)        → Open URL in browser
✅ system:vibrate()                → Vibrate device
✅ system:copy_to_clipboard(text)  → Copy text to clipboard

❌ DOES NOT EXIST: system:log, system:print, system:notify, system:alert

📲 CALLBACK FUNCTIONS (define these in your script)
─────────────────────────────────────────────────────────────────────────────
✅ function on_resume()            → Called when widget loads/becomes visible
✅ function on_click()             → Called when user taps widget
✅ function on_long_click()        → Called on long press
✅ function on_alarm()             → Called by scheduled alarm
✅ function on_network_result(result, code) → HTTP response callback (DEPRECATED - use inline callbacks)

🔤 STRING/UTILITY FUNCTIONS (Lua standard library)
─────────────────────────────────────────────────────────────────────────────
✅ string.format(fmt, ...)         → Format string
✅ string.sub(s, i, j)             → Substring
✅ string.gsub(s, pattern, repl)   → Pattern replace
✅ string.match(s, pattern)        → Pattern match
✅ string.len(s)                   → String length
✅ tonumber(s)                     → Convert to number
✅ tostring(n)                     → Convert to string
✅ math.floor(n), math.ceil(n)     → Math operations
✅ table.insert(t, v)              → Insert into table
✅ table.concat(t, sep)            → Join table elements
✅ pairs(t), ipairs(t)             → Table iteration
✅ pcall(func, ...)                → Protected call (error handling)

═══════════════════════════════════════════════════════════════════════════════
                              ⚠️ CRITICAL RULES ⚠️
═══════════════════════════════════════════════════════════════════════════════
1. NEVER add functions that don't exist in the list above
2. NEVER use http:set_headers() - headers go as 2nd param to http:get/post
3. NEVER use json:decode() - use json.decode() (DOT not COLON)
4. NEVER invent new APIs - if unsure, DON'T use it
5. Keep the original script structure - only fix actual errors
6. If the script works, make MINIMAL changes
═══════════════════════════════════════════════════════════════════════════════
`;

app.post('/api/inspector/analyze', async (req, res) => {
    try {
        const { script, apiKey } = req.body;

        if (!script) {
            return res.status(400).json({ error: 'No script provided' });
        }

        if (!apiKey) {
            return res.status(400).json({ error: 'No API key provided' });
        }

        const systemPrompt = `You are an expert AIO Launcher Lua widget script analyzer.

${AIO_API_REFERENCE}

YOUR TASK: Review the script and provide feedback using ONLY the APIs listed above.

ANALYSIS FORMAT:

### Script Purpose
One sentence describing what this widget does.

### API Check
- ✅ Correct: [list correct API usage]
- ❌ Errors: [list any wrong API calls with line numbers]

### Issues Found
List actual problems (not theoretical improvements):
- Missing nil checks that could crash
- Hardcoded credentials (security risk)
- Logic errors

### Improved Script
\`\`\`lua
-- Enhanced by AIO Widget Emulator by Phenix
-- ONLY fix actual errors, keep everything else the same
-- DO NOT add new features or restructure working code
[your improved code here]
\`\`\`

⚠️ CRITICAL INSTRUCTIONS:
1. ONLY use APIs from the reference above - NEVER invent new ones
2. If http:set_headers appears - REMOVE IT (doesn't exist)
3. Headers go as 2nd parameter: http:get(url, {["Auth"]="xxx"}, callback)
4. Use json.decode() NOT json:decode() (dot, not colon)
5. If the script already works, make MINIMAL changes
6. DO NOT restructure working code
7. DO NOT add features the original didn't have
8. Keep the original variable names and structure`;

        // Use Groq API (free tier with fast inference)
        const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${apiKey}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                model: 'llama-3.3-70b-versatile',
                messages: [
                    { role: 'system', content: systemPrompt },
                    { role: 'user', content: `Analyze this AIO Launcher widget script:\n\n\`\`\`lua\n${script}\n\`\`\`` }
                ],
                temperature: 0.3,
                max_tokens: 4000
            })
        });

        if (!response.ok) {
            const errorData = await response.json().catch(() => ({}));
            console.error('Groq API error:', errorData);
            return res.status(response.status).json({
                error: errorData.error?.message || `API error: ${response.status}`
            });
        }

        const data = await response.json();
        const analysis = data.choices?.[0]?.message?.content || 'No analysis generated';

        // Log the analysis for review and debugging
        logInspectorAnalysis(script, analysis, true);

        res.json({ success: true, analysis });

    } catch (error) {
        console.error('Inspector error:', error);
        logInspectorAnalysis(script || 'No script', error.message, false);
        res.status(500).json({ error: error.message });
    }
});

app.listen(PORT, () => {
    console.log(`🚀 Visual Emulator running at http://localhost:${PORT}`);
    console.log(`📱 Open your browser and navigate to the URL above`);
});


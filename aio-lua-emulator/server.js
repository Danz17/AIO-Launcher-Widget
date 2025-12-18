#!/usr/bin/env node

// Web Server for Visual Emulator
import express from 'express';
import cors from 'cors';
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';
import { lua, lauxlib, lualib, to_luastring } from 'fengari';
import { ui, clearOutput, getOutputBuffer } from './api/ui.js';
import { http, loadMocks, setHttpMode } from './api/http.js';
import { json } from './api/json.js';
import { system } from './api/system.js';
import { android } from './api/android.js';

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
            throw new Error(`Error calling ${name}: ${error}`);
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
        
        // Load script
        loadScript(L, script);
        
        // Wait a bit for async operations
        await new Promise(resolve => setTimeout(resolve, 100));
        
        // Call function if specified, otherwise call on_resume
        const funcToCall = functionName || 'on_resume';
        const exists = callLuaFunction(L, funcToCall);
        
        // Wait for async operations to complete
        await new Promise(resolve => setTimeout(resolve, 500));
        
        // Get output
        const output = getOutputBuffer();
        
        res.json({
            success: true,
            output: output,
            functionExists: exists
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
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
        const mikrotikDir = resolve(__dirname, '..', 'Mikrotik');
        const widgets = [];
        
        // Scan Widgets directory
        if (existsSync(widgetsDir)) {
            const files = readdirSync(widgetsDir)
                .filter(f => f.endsWith('.lua'))
                .map(f => ({
                    name: f.replace('.lua', ''),
                    path: join(widgetsDir, f),
                    category: 'Widgets'
                }));
            widgets.push(...files);
        }
        
        // Scan Mikrotik directory
        if (existsSync(mikrotikDir)) {
            const files = readdirSync(mikrotikDir)
                .filter(f => f.endsWith('.lua'))
                .map(f => ({
                    name: 'MikroTik - ' + f.replace('.lua', ''),
                    path: join(mikrotikDir, f),
                    category: 'MikroTik'
                }));
            widgets.push(...files);
        }
        
        res.json(widgets);
    } catch (error) {
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

app.listen(PORT, () => {
    console.log(`🚀 Visual Emulator running at http://localhost:${PORT}`);
    console.log(`📱 Open your browser and navigate to the URL above`);
});


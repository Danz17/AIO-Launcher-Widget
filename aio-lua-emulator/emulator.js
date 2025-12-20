#!/usr/bin/env node

// Main Lua Emulator for AIO Launcher Scripts
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';
import { program } from 'commander';
import inquirer from 'inquirer';
import chalk from 'chalk';
import { lua, lauxlib, lualib, to_luastring } from 'fengari';
import { ui, selectMenuOption, hasContextMenu, getContextMenuItems, clearOutput } from './api/ui.js';
import { http, loadMocks, isUsingMocks } from './api/http.js';
import { json } from './api/json.js';
import { system } from './api/system.js';
import { storage, files } from './api/storage.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Lua state
let L;
let scriptPath = null;
let interactiveMode = false;

// Initialize Lua state and APIs
function initLua() {
    L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    
    // Create ui module with all display functions
    lua.lua_createtable(L, 0, 12);
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_text, true));
    lua.lua_setfield(L, -2, to_luastring("show_text"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_lines, true));
    lua.lua_setfield(L, -2, to_luastring("show_lines"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_buttons, true));
    lua.lua_setfield(L, -2, to_luastring("show_buttons"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_table, true));
    lua.lua_setfield(L, -2, to_luastring("show_table"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_progress_bar, true));
    lua.lua_setfield(L, -2, to_luastring("show_progress_bar"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_chart, true));
    lua.lua_setfield(L, -2, to_luastring("show_chart"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_toast, true));
    lua.lua_setfield(L, -2, to_luastring("show_toast"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.set_title, true));
    lua.lua_setfield(L, -2, to_luastring("set_title"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.set_expandable, true));
    lua.lua_setfield(L, -2, to_luastring("set_expandable"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.is_folded, true));
    lua.lua_setfield(L, -2, to_luastring("is_folded"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.is_expanded, true));
    lua.lua_setfield(L, -2, to_luastring("is_expanded"));
    lua.lua_pushcfunction(L, luaWrapFunction(ui.show_context_menu, true));
    lua.lua_setfield(L, -2, to_luastring("show_context_menu"));
    lua.lua_setglobal(L, to_luastring("ui"));
    
    // Create http module
    lua.lua_createtable(L, 0, 2);
    lua.lua_pushcfunction(L, luaWrapFunction(http.get, true)); // Skip first arg (module itself)
    lua.lua_setfield(L, -2, to_luastring("get"));
    lua.lua_pushcfunction(L, luaWrapFunction(http.post, true)); // Skip first arg (module itself)
    lua.lua_setfield(L, -2, to_luastring("post"));
    lua.lua_setglobal(L, to_luastring("http"));
    
    // Create json module
    lua.lua_createtable(L, 0, 2);
    lua.lua_pushcfunction(L, luaWrapFunction(json.decode, true)); // Skip first arg (module itself)
    lua.lua_setfield(L, -2, to_luastring("decode"));
    lua.lua_pushcfunction(L, luaWrapFunction(json.encode, true)); // Skip first arg (module itself)
    lua.lua_setfield(L, -2, to_luastring("encode"));
    lua.lua_setglobal(L, to_luastring("json"));
    
    // Create system module
    lua.lua_createtable(L, 0, 2);
    lua.lua_pushcfunction(L, luaWrapFunction(system.open_browser));
    lua.lua_setfield(L, -2, to_luastring("open_browser"));
    lua.lua_pushcfunction(L, luaWrapFunction(system.toast));
    lua.lua_setfield(L, -2, to_luastring("toast"));
    lua.lua_setglobal(L, to_luastring("system"));

    // Create storage module for persistent data
    lua.lua_createtable(L, 0, 6);
    lua.lua_pushcfunction(L, luaWrapFunction(storage.get, true));
    lua.lua_setfield(L, -2, to_luastring("get"));
    lua.lua_pushcfunction(L, luaWrapFunction(storage.set, true));
    lua.lua_setfield(L, -2, to_luastring("set"));
    lua.lua_pushcfunction(L, luaWrapFunction(storage.delete, true));
    lua.lua_setfield(L, -2, to_luastring("delete"));
    lua.lua_pushcfunction(L, luaWrapFunction(storage.has, true));
    lua.lua_setfield(L, -2, to_luastring("has"));
    lua.lua_pushcfunction(L, luaWrapFunction(storage.keys, true));
    lua.lua_setfield(L, -2, to_luastring("keys"));
    lua.lua_pushcfunction(L, luaWrapFunction(storage.clear, true));
    lua.lua_setfield(L, -2, to_luastring("clear"));
    lua.lua_setglobal(L, to_luastring("storage"));

    // Create files module for file I/O
    lua.lua_createtable(L, 0, 3);
    lua.lua_pushcfunction(L, luaWrapFunction(files.read, true));
    lua.lua_setfield(L, -2, to_luastring("read"));
    lua.lua_pushcfunction(L, luaWrapFunction(files.write, true));
    lua.lua_setfield(L, -2, to_luastring("write"));
    lua.lua_pushcfunction(L, luaWrapFunction(files.exists, true));
    lua.lua_setfield(L, -2, to_luastring("exists"));
    lua.lua_setglobal(L, to_luastring("files"));
}

// Wrap JavaScript function for Lua
function luaWrapFunction(fn, skipFirst = false) {
    return function(L) {
        const nargs = lua.lua_gettop(L);
        const args = [];
        const startIdx = skipFirst ? 2 : 1; // Skip first arg if it's the module itself (for : syntax)
        
        // Get arguments from Lua stack
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
                // Wrap Lua function as callback
                args.push(createLuaCallback(L, i));
            } else {
                args.push(null);
            }
        }
        
        // Call JavaScript function
        try {
            const result = fn.apply(null, args);
            
            // Push result back to Lua stack if any
            if (result !== undefined && result !== null) {
                if (typeof result === 'string') {
                    lua.lua_pushstring(L, to_luastring(result));
                } else if (typeof result === 'number') {
                    lua.lua_pushnumber(L, result);
                } else if (typeof result === 'boolean') {
                    lua.lua_pushboolean(L, result);
                } else if (typeof result === 'object') {
                    // Convert JavaScript object/array to Lua table
                    jsToLuaTable(L, result);
                } else {
                    lua.lua_pushnil(L);
                }
                return 1;
            }
        } catch (e) {
            console.error(chalk.red(`Error in ${fn.name}: ${e.message}`));
            lua.lua_pushnil(L);
            return 1;
        }
        
        return 0;
    };
}

// Create Lua callback function
function createLuaCallback(L, index) {
    // Store the Lua function reference
    lua.lua_pushvalue(L, index);
    const ref = lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX);
    
    return function(...args) {
        // Get the function from registry
        lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, ref);
        
        // Push arguments
        for (const arg of args) {
            if (typeof arg === 'string') {
                lua.lua_pushstring(L, arg);
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
        
        // Call the Lua function
        const result = lua.lua_pcall(L, args.length, 0, 0);
        if (result !== lua.LUA_OK) {
            const error = lua.lua_tojsstring(L, -1);
            console.error(chalk.red(`Lua callback error: ${error}`));
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

// Load and run Lua script
function loadScript(filePath) {
    try {
        const script = readFileSync(filePath, 'utf8');
        scriptPath = filePath;
        
        console.log(chalk.green(`\n✓ Loaded script: ${filePath}\n`));
        
        // Execute script (convert to Lua string first)
        const status = lauxlib.luaL_loadstring(L, to_luastring(script));
        if (status !== lua.LUA_OK) {
            let error = 'Unknown error';
            if (lua.lua_type(L, -1) === lua.LUA_TSTRING) {
                error = lua.lua_tostring(L, -1) || error;
            }
            lua.lua_pop(L, 1); // Remove error from stack
            throw new Error(`Lua load error: ${error}`);
        }
        
        // Run the script
        const result = lua.lua_pcall(L, 0, 0, 0);
        if (result !== lua.LUA_OK) {
            let error = 'Unknown error';
            if (lua.lua_type(L, -1) === lua.LUA_TSTRING) {
                error = lua.lua_tostring(L, -1) || error;
            }
            lua.lua_pop(L, 1); // Remove error from stack
            throw new Error(`Lua runtime error: ${error}`);
        }
        
        return true;
    } catch (e) {
        console.error(chalk.red(`\n✗ Error loading script: ${e.message}\n`));
        if (e.stack) {
            console.error(chalk.gray(e.stack));
        }
        return false;
    }
}

// Call Lua function
function callLuaFunction(name, ...args) {
    lua.lua_getglobal(L, to_luastring(name));
    if (lua.lua_isfunction(L, -1)) {
        // Push arguments
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
        
        // Call function
        const result = lua.lua_pcall(L, args.length, 0, 0);
        if (result !== lua.LUA_OK) {
            const error = lua.lua_tojsstring(L, -1);
            console.error(chalk.red(`Error calling ${name}: ${error}`));
            return false;
        }
        return true;
    } else {
        console.log(chalk.yellow(`Function ${name} not found in script`));
        lua.lua_pop(L, 1);
        return false;
    }
}

// Wait for async operations
function waitForAsync() {
    return new Promise(resolve => setTimeout(resolve, 1000));
}

// Interactive mode
async function runInteractive() {
    interactiveMode = true;
    
    console.log(chalk.bold.cyan('\n━━━━━━━━━━━━━━━━━━━━━━━━━'));
    console.log(chalk.bold.cyan('AIO Launcher Lua Emulator'));
    console.log(chalk.bold.cyan('Interactive Mode'));
    console.log(chalk.bold.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
    
    while (true) {
        const choices = [
            { name: 'Run on_resume()', value: 'resume' },
            { name: 'Simulate on_click()', value: 'click' },
            { name: 'Simulate on_long_click()', value: 'longclick' },
            { name: 'Exit', value: 'exit' }
        ];
        
        if (hasContextMenu()) {
            choices.splice(3, 0, { name: 'Select context menu item', value: 'menu' });
        }
        
        const { action } = await inquirer.prompt([
            {
                type: 'list',
                name: 'action',
                message: 'What would you like to do?',
                choices: choices
            }
        ]);
        
        if (action === 'exit') {
            console.log(chalk.green('\n👋 Goodbye!\n'));
            break;
        } else if (action === 'resume') {
            console.log(chalk.blue('\n▶ Running on_resume()...\n'));
            callLuaFunction('on_resume');
            await waitForAsync();
        } else if (action === 'click') {
            console.log(chalk.blue('\n▶ Running on_click()...\n'));
            callLuaFunction('on_click');
            await waitForAsync();
        } else if (action === 'longclick') {
            console.log(chalk.blue('\n▶ Running on_long_click()...\n'));
            callLuaFunction('on_long_click');
            await waitForAsync();
            
            if (hasContextMenu()) {
                const items = getContextMenuItems();
                const { choice } = await inquirer.prompt([
                    {
                        type: 'list',
                        name: 'choice',
                        message: 'Select menu item:',
                        choices: items.map((item, idx) => ({
                            name: item,
                            value: idx + 1
                        })).concat([{ name: 'Cancel', value: 0 }])
                    }
                ]);
                
                console.log(chalk.blue(`\n▶ Running on_context_menu_click(${choice})...\n`));
                callLuaFunction('on_context_menu_click', choice);
                await waitForAsync();
            }
        } else if (action === 'menu' && hasContextMenu()) {
            const items = getContextMenuItems();
            const { choice } = await inquirer.prompt([
                {
                    type: 'list',
                    name: 'choice',
                    message: 'Select menu item:',
                    choices: items.map((item, idx) => ({
                        name: item,
                        value: idx + 1
                    })).concat([{ name: 'Cancel', value: 0 }])
                }
            ]);
            
            console.log(chalk.blue(`\n▶ Running on_context_menu_click(${choice})...\n`));
            callLuaFunction('on_context_menu_click', choice);
            await waitForAsync();
        }
    }
}

// Main function
async function main() {
    program
        .name('aio-emulator')
        .description('AIO Launcher Lua script emulator')
        .version('1.0.0')
        .argument('<script>', 'Lua script file to run')
        .option('-m, --mock <file>', 'Load mock data from JSON file')
        .option('-i, --interactive', 'Run in interactive mode')
        .option('-t, --test <function>', 'Test specific function')
        .action(async (script, options) => {
            const scriptPath = resolve(script);
            
            // Initialize Lua
            initLua();
            
            // Load mocks if specified
            if (options.mock) {
                loadMocks(options.mock);
            }
            
            // Load script
            if (!loadScript(scriptPath)) {
                process.exit(1);
            }
            
            // Run specific test or default
            if (options.test) {
                console.log(chalk.blue(`\n▶ Testing function: ${options.test}()\n`));
                callLuaFunction(options.test);
                await waitForAsync();
            } else if (options.interactive) {
                // Run on_resume first, then enter interactive mode
                callLuaFunction('on_resume');
                await waitForAsync();
                await runInteractive();
            } else {
                // Just run on_resume
                console.log(chalk.blue('\n▶ Running on_resume()...\n'));
                callLuaFunction('on_resume');
                await waitForAsync();
                
                console.log(chalk.green('\n✓ Script execution complete\n'));
            }
        });
    
    program.parse();
}

main().catch(console.error);

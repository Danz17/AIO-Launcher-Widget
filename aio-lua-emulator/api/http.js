// HTTP API Emulation for AIO Launcher
import chalk from 'chalk';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import fetch from 'node-fetch';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

let mockData = {};
let useMocks = true;  // Default to mock mode
let mockFile = null;
let httpMode = 'mock';

// Load mock data from JSON file
export function loadMocks(filePath) {
    try {
        const fullPath = join(process.cwd(), filePath);
        const data = readFileSync(fullPath, 'utf8');
        mockData = JSON.parse(data);
        useMocks = true;
        mockFile = filePath;
        console.log(chalk.green(`✓ Loaded mock data from ${filePath}`));
        return true;
    } catch (e) {
        console.log(chalk.red(`✗ Failed to load mocks: ${e.message}`));
        return false;
    }
}

// Extract URL from various formats
function normalizeUrl(url) {
    // Remove auth from URL for matching: http://user:pass@host/path -> http://host/path
    return url.replace(/:\/\/[^@]+@/, '://');
}

// Get mock response for URL
function getMockResponse(url) {
    const normalized = normalizeUrl(url);
    
    // Try exact match first
    if (mockData[url]) {
        return mockData[url];
    }
    if (mockData[normalized]) {
        return mockData[normalized];
    }
    
    // Try path-only match (for cases where only path is in mock)
    const urlObj = new URL(url);
    const pathOnly = urlObj.pathname;
    if (mockData[pathOnly]) {
        return mockData[pathOnly];
    }
    
    // Try partial match (for query params or different hosts)
    for (const key in mockData) {
        const keyPath = key.includes('://') ? new URL(key).pathname : key;
        if (normalized.includes(key) || key.includes(normalized.split('?')[0]) || 
            pathOnly === keyPath || pathOnly.includes(keyPath) || keyPath.includes(pathOnly)) {
            return mockData[key];
        }
    }
    
    return null;
}


export const http = {
    get: function(url, callbackOrBody, headersOrCallback, maybeHeaders) {
        // Handle both formats:
        // Format 1: http:get(url, callback, headers)
        // Format 2: http:get(url, "", callback, headers) - AIO Launcher format
        
        let callback, headers;
        
        if (typeof callbackOrBody === 'function') {
            // Format 1: http:get(url, callback, headers)
            callback = callbackOrBody;
            headers = headersOrCallback;
        } else {
            // Format 2: http:get(url, "", callback, headers)
            callback = headersOrCallback;
            headers = maybeHeaders;
        }
        
        // Convert URL to string if it's a Lua string object
        let urlStr = url;
        if (typeof url !== 'string') {
            console.log(chalk.gray(`   DEBUG: URL type: ${typeof url}, value: ${JSON.stringify(url)}`));
            // Try to convert Lua string object
            if (url && typeof url.toString === 'function') {
                urlStr = url.toString();
            } else {
                urlStr = String(url);
            }
        }
        console.log(chalk.blue(`\n📡 HTTP GET: ${urlStr}`));
        if (headers) {
            console.log(chalk.gray(`   Headers: ${JSON.stringify(headers)}`));
        } else {
            console.log(chalk.yellow(`   Headers: undefined (no auth)`));
        }
        console.log(chalk.gray(`   Mode: ${useMocks ? 'MOCK' : 'REAL'}`));
        
        // Simulate async HTTP request
        setTimeout(() => {
            if (useMocks) {
                const mock = getMockResponse(urlStr);
                if (mock) {
                    console.log(chalk.green(`   ✓ Mock response found (status: ${mock.status || 200})`));
                    
                    // Simulate network delay
                    setTimeout(() => {
                        // Always return as JSON string for consistency
                        const responseBody = typeof mock.body === 'object' 
                            ? JSON.stringify(mock.body) 
                            : (typeof mock.body === 'string' ? mock.body : JSON.stringify(mock.body));
                        
                        if (callback) {
                            callback(responseBody, mock.status || 200);
                        }
                    }, 50);
                    return;
                } else {
                    console.log(chalk.yellow(`   ⚠ No mock found for URL: ${urlStr}`));
                    console.log(chalk.yellow(`   Available mocks: ${Object.keys(mockData).join(', ')}`));
                    if (callback) {
                        callback(null, 404);
                    }
                    return;
                }
            }
            
            // Real HTTP request (if mocks not enabled)
            console.log(chalk.cyan(`   🌐 Making REAL HTTP request...`));
            fetch(urlStr, { headers: headers || {} })
                .then(response => {
                    const status = response.status;
                    return response.text().then(data => ({ data, status }));
                })
                .then(({ data, status }) => {
                    console.log(chalk.green(`   ✓ Response: ${status}`));
                    console.log(chalk.gray(`   Data preview: ${data.substring(0, 100)}...`));
                    if (callback) {
                        callback(data, status);
                    }
                })
                .catch(e => {
                    console.log(chalk.red(`   ✗ Error: ${e.message}`));
                    if (callback) {
                        callback(null, 0);
                    }
                });
        }, 10);
    },
    
    post: function(url, body, callback, headers) {
        // Convert URL to string if it's a Lua string object
        const urlStr = (typeof url === 'string') ? url : String(url);
        console.log(chalk.blue(`\n📡 HTTP POST: ${urlStr}`));
        console.log(chalk.gray(`   Body: ${typeof body === 'string' ? body : JSON.stringify(body)}`));
        if (headers) {
            console.log(chalk.gray(`   Headers: ${JSON.stringify(headers)}`));
        }
        
        // Simulate async HTTP request
        setTimeout(() => {
            if (useMocks) {
                const mock = getMockResponse(urlStr);
                if (mock) {
                    console.log(chalk.green(`   ✓ Mock response found`));
                    
                    setTimeout(() => {
                        const responseBody = typeof mock.body === 'object' 
                            ? JSON.stringify(mock.body) 
                            : mock.body;
                        
                        if (callback) {
                            callback(responseBody, mock.status || 200);
                        }
                    }, 50);
                    return;
                } else {
                    console.log(chalk.yellow(`   ⚠ No mock found, simulating success`));
                    if (callback) {
                        callback('{"success": true}', 200);
                    }
                    return;
                }
            }
            
            // Real HTTP request
            fetch(urlStr, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...(headers || {})
                },
                body: typeof body === 'string' ? body : JSON.stringify(body)
            })
                .then(response => response.text())
                .then(data => {
                    console.log(chalk.green(`   ✓ Response: 200`));
                    if (callback) {
                        callback(data, 200);
                    }
                })
                .catch(e => {
                    console.log(chalk.red(`   ✗ Error: ${e.message}`));
                    if (callback) {
                        callback(null, 0);
                    }
                });
        }, 10);
    }
};

export function isUsingMocks() {
    return useMocks;
}

export function setHttpMode(mode) {
    httpMode = mode;
    useMocks = (mode === 'mock');
    console.log(chalk.cyan(`📡 HTTP mode set to: ${mode}`));
}

export function getMockFile() {
    return mockFile;
}


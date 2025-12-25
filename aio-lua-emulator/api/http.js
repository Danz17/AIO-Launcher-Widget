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
let httpLogCallback = null;  // Callback to send logs to frontend
let globalHeaders = {};  // Headers set via http:set_headers()

// Set callback for HTTP logging
export function setHttpLogCallback(callback) {
    httpLogCallback = callback;
}

// Send detailed log to frontend
function sendHttpLog(type, details) {
    if (httpLogCallback) {
        httpLogCallback(type, details);
    }
}

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

// Get HTTP status text
function getStatusText(status) {
    const statusTexts = {
        200: 'OK', 201: 'Created', 204: 'No Content',
        400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden',
        404: 'Not Found', 408: 'Request Timeout', 429: 'Too Many Requests',
        500: 'Internal Server Error', 502: 'Bad Gateway', 503: 'Service Unavailable',
        504: 'Gateway Timeout'
    };
    return statusTexts[status] || 'Unknown';
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
    // Set global headers for all subsequent requests
    set_headers: function(headers) {
        if (Array.isArray(headers)) {
            // Format: {"Header1: value1", "Header2: value2"}
            globalHeaders = {};
            headers.forEach(h => {
                if (typeof h === 'string') {
                    const colonIdx = h.indexOf(':');
                    if (colonIdx > 0) {
                        const key = h.substring(0, colonIdx).trim();
                        const value = h.substring(colonIdx + 1).trim();
                        globalHeaders[key] = value;
                    }
                }
            });
        } else if (typeof headers === 'object' && headers !== null) {
            // Format: {["Header1"] = "value1", ["Header2"] = "value2"}
            globalHeaders = { ...headers };
        }
        console.log(chalk.gray(`[HTTP] Global headers set: ${JSON.stringify(globalHeaders)}`));
    },

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

        // Merge global headers with request-specific headers
        const mergedHeaders = { ...globalHeaders, ...(headers || {}) };
        headers = Object.keys(mergedHeaders).length > 0 ? mergedHeaders : null;

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
        const requestId = Date.now() + Math.random();
        const requestDetails = {
            method: 'GET',
            url: urlStr,
            headers: headers || {},
            timestamp: new Date().toISOString()
        };
        
        console.log(chalk.blue(`\n📡 HTTP GET: ${urlStr}`));
        if (headers && Object.keys(headers).length > 0) {
            console.log(chalk.gray(`   Headers: ${JSON.stringify(headers)}`));
        } else {
            console.log(chalk.gray(`   Headers: (none)`));
        }
        console.log(chalk.gray(`   Mode: ${useMocks ? 'MOCK' : 'REAL'}`));
        
        // Log request start
        sendHttpLog('request', {
            id: requestId,
            ...requestDetails,
            mode: useMocks ? 'MOCK' : 'REAL'
        });
        
        // Simulate async HTTP request
        setTimeout(() => {
            if (useMocks) {
                const mock = getMockResponse(urlStr);
                if (mock) {
                    const status = mock.status || 200;
                    const responseBody = typeof mock.body === 'object' 
                        ? JSON.stringify(mock.body) 
                        : (typeof mock.body === 'string' ? mock.body : JSON.stringify(mock.body));
                    
                    console.log(chalk.green(`   ✓ Mock response found (status: ${status})`));

                    // Log successful mock response with enhanced details
                    const mockDuration = Math.floor(20 + Math.random() * 80);
                    sendHttpLog('response', {
                        id: requestId,
                        status: status,
                        statusText: getStatusText(status),
                        headers: {
                            'content-type': 'application/json',
                            'x-mock-response': 'true'
                        },
                        body: responseBody,
                        bodyPreview: responseBody.substring(0, 500),
                        mode: 'MOCK',
                        duration: mockDuration,
                        ok: status >= 200 && status < 300,
                        requestUrl: urlStr,
                        requestHeaders: headers || {},
                        requestMethod: 'GET'
                    });

                    // Simulate network delay
                    setTimeout(() => {
                        if (callback) {
                            callback(responseBody, status);
                        }
                    }, mockDuration);
                    return;
                } else {
                    const availableMocks = Object.keys(mockData);
                    const errorMsg = `No mock data found for URL`;
                    const suggestion = availableMocks.length > 0 
                        ? `Available mocks: ${availableMocks.slice(0, 5).join(', ')}${availableMocks.length > 5 ? '...' : ''}`
                        : 'No mock data file loaded. Add mock data or switch to REAL mode.';
                    
                    console.log(chalk.yellow(`   ⚠ ${errorMsg}: ${urlStr}`));
                    console.log(chalk.yellow(`   ${suggestion}`));
                    
                    // Log mock not found error
                    sendHttpLog('error', {
                        id: requestId,
                        type: 'MOCK_NOT_FOUND',
                        message: errorMsg,
                        url: urlStr,
                        suggestion: suggestion,
                        availableMocks: availableMocks,
                        fix: 'Add this URL to your mock JSON file or enable REAL HTTP mode'
                    });
                    
                    if (callback) {
                        callback(null, 404);
                    }
                    return;
                }
            }
            
            // Real HTTP request (if mocks not enabled)
            console.log(chalk.cyan(`   🌐 Making REAL HTTP request...`));
            const startTime = Date.now();
            
            // Create timeout controller
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 30000);
            
            fetch(urlStr, { 
                headers: headers || {},
                signal: controller.signal
            })
                .then(response => {
                    const status = response.status;
                    const responseHeaders = {};
                    response.headers.forEach((value, key) => {
                        responseHeaders[key] = value;
                    });
                    
                    return response.text().then(data => ({ 
                        data, 
                        status, 
                        headers: responseHeaders,
                        ok: response.ok
                    }));
                })
                .then(({ data, status, headers: responseHeaders, ok }) => {
                    clearTimeout(timeoutId);
                    const duration = Date.now() - startTime;
                    
                    // Log response with full details
                    sendHttpLog('response', {
                        id: requestId,
                        status: status,
                        statusText: getStatusText(status),
                        headers: responseHeaders,
                        body: data,
                        bodyPreview: data.substring(0, 200),
                        mode: 'REAL',
                        duration: duration,
                        ok: ok,
                        requestUrl: urlStr,
                        requestHeaders: headers || {},
                        requestMethod: 'GET'
                    });
                    
                    if (!ok) {
                        // HTTP error status (4xx, 5xx)
                        let errorType = 'HTTP_ERROR';
                        let suggestion = '';
                        let fix = '';
                        
                        if (status >= 400 && status < 500) {
                            errorType = 'CLIENT_ERROR';
                            if (status === 401) {
                                suggestion = 'Authentication failed. The server rejected your credentials or API key.';
                                fix = '1. Check if Authorization header is correct\n2. Verify API key/credentials are valid\n3. Check if token has expired\n4. Ensure auth format matches API requirements (Basic, Bearer, etc.)';
                            } else if (status === 403) {
                                suggestion = 'Access forbidden. Your credentials are valid but you lack permission.';
                                fix = '1. Check API key permissions/scope\n2. Verify user account has required access\n3. Check if IP whitelist is enabled';
                            } else if (status === 404) {
                                suggestion = 'Resource not found. The URL path does not exist on the server.';
                                fix = '1. Verify the API endpoint URL is correct\n2. Check API documentation for correct path\n3. Ensure API version is correct (e.g., /api/v1 vs /api/v2)';
                            } else if (status === 400) {
                                suggestion = 'Bad request. The server could not understand your request.';
                                fix = '1. Check request parameters/query strings\n2. Verify request body format (JSON, XML, etc.)\n3. Check required fields are present';
                            } else {
                                suggestion = 'Client error. Your request was invalid or malformed.';
                                fix = '1. Review request parameters\n2. Check request format matches API spec\n3. Verify authentication is correct';
                            }
                        } else if (status >= 500) {
                            errorType = 'SERVER_ERROR';
                            suggestion = 'Server error. The API server encountered an internal error.';
                            fix = '1. Server may be temporarily down - try again later\n2. Check API status page if available\n3. Contact API provider if issue persists';
                        }
                        
                        sendHttpLog('error', {
                            id: requestId,
                            type: errorType,
                            message: `HTTP ${status} ${getStatusText(status)}`,
                            status: status,
                            url: urlStr,
                            body: data,
                            bodyPreview: data.substring(0, 500),
                            suggestion: suggestion,
                            fix: fix,
                            requestHeaders: headers || {},
                            responseHeaders: responseHeaders,
                            duration: duration
                        });
                    }
                    
                    console.log(chalk.green(`   ✓ Response: ${status} ${getStatusText(status)}`));
                    console.log(chalk.gray(`   Duration: ${duration}ms`));
                    console.log(chalk.gray(`   Data preview: ${data.substring(0, 100)}...`));
                    
                    if (callback) {
                        callback(data, status);
                    }
                })
                .catch(e => {
                    const duration = Date.now() - startTime;
                    let errorType = 'NETWORK_ERROR';
                    let suggestion = '';
                    let fix = '';
                    
                    // Categorize error
                    if (e.name === 'AbortError' || e.message.includes('timeout')) {
                        errorType = 'TIMEOUT';
                        suggestion = 'Request timed out. The server may be slow or unreachable.';
                        fix = 'Increase timeout or check network connection';
                    } else if (e.code === 'ENOTFOUND' || e.message.includes('getaddrinfo')) {
                        errorType = 'DNS_ERROR';
                        suggestion = 'DNS lookup failed. The hostname cannot be resolved.';
                        fix = 'Check the URL hostname for typos';
                    } else if (e.code === 'ECONNREFUSED' || e.message.includes('ECONNREFUSED')) {
                        errorType = 'CONNECTION_REFUSED';
                        suggestion = 'Connection refused. The server is not accepting connections.';
                        fix = 'Check if the server is running and the port is correct';
                    } else if (e.code === 'ECONNRESET') {
                        errorType = 'CONNECTION_RESET';
                        suggestion = 'Connection was reset by the server.';
                        fix = 'The server may have closed the connection. Try again.';
                    } else if (e.message.includes('CORS')) {
                        errorType = 'CORS_ERROR';
                        suggestion = 'CORS policy blocked the request.';
                        fix = 'The API server needs to allow CORS or use a CORS proxy';
                    } else if (e.message.includes('certificate') || e.message.includes('SSL')) {
                        errorType = 'SSL_ERROR';
                        suggestion = 'SSL/TLS certificate error.';
                        fix = 'Check SSL certificate validity or use HTTP instead of HTTPS';
                    } else {
                        suggestion = e.message || 'Unknown network error occurred.';
                        fix = 'Check network connection and server availability';
                    }
                    
                    console.log(chalk.red(`   ✗ Error: ${e.message}`));
                    if (e.stack) {
                        console.log(chalk.gray(`   Stack: ${e.stack}`));
                    }
                    
                    // Log detailed error
                    sendHttpLog('error', {
                        id: requestId,
                        type: errorType,
                        message: e.message,
                        code: e.code,
                        url: urlStr,
                        duration: duration,
                        suggestion: suggestion,
                        fix: fix,
                        stack: e.stack
                    });
                    
                    if (callback) {
                        callback(null, 0);
                    }
                });
        }, 10);
    },
    
    post: function(url, body, callback, headers) {
        // Convert URL to string if it's a Lua string object
        const urlStr = (typeof url === 'string') ? url : String(url);
        const requestId = Date.now() + Math.random();
        const bodyStr = typeof body === 'string' ? body : JSON.stringify(body);

        // Merge global headers with request-specific headers
        const mergedHeaders = { ...globalHeaders, ...(headers || {}) };
        headers = Object.keys(mergedHeaders).length > 0 ? mergedHeaders : null;

        const requestDetails = {
            method: 'POST',
            url: urlStr,
            body: bodyStr,
            bodyPreview: bodyStr.substring(0, 200),
            headers: headers || {},
            timestamp: new Date().toISOString()
        };
        
        console.log(chalk.blue(`\n📡 HTTP POST: ${urlStr}`));
        console.log(chalk.gray(`   Body: ${bodyStr.substring(0, 100)}${bodyStr.length > 100 ? '...' : ''}`));
        if (headers) {
            console.log(chalk.gray(`   Headers: ${JSON.stringify(headers)}`));
        }
        console.log(chalk.gray(`   Mode: ${useMocks ? 'MOCK' : 'REAL'}`));
        
        // Log request start
        sendHttpLog('request', {
            id: requestId,
            ...requestDetails,
            mode: useMocks ? 'MOCK' : 'REAL'
        });
        
        // Simulate async HTTP request
        setTimeout(() => {
            if (useMocks) {
                const mock = getMockResponse(urlStr);
                if (mock) {
                    const status = mock.status || 200;
                    const responseBody = typeof mock.body === 'object' 
                        ? JSON.stringify(mock.body) 
                        : mock.body;
                    
                    console.log(chalk.green(`   ✓ Mock response found (status: ${status})`));

                    // Log successful mock response with enhanced details
                    const mockDuration = Math.floor(30 + Math.random() * 100);
                    sendHttpLog('response', {
                        id: requestId,
                        status: status,
                        statusText: getStatusText(status),
                        headers: {
                            'content-type': 'application/json',
                            'x-mock-response': 'true'
                        },
                        body: responseBody,
                        bodyPreview: responseBody.substring(0, 500),
                        mode: 'MOCK',
                        duration: mockDuration,
                        ok: status >= 200 && status < 300,
                        requestUrl: urlStr,
                        requestHeaders: headers || {},
                        requestMethod: 'POST'
                    });

                    setTimeout(() => {
                        if (callback) {
                            callback(responseBody, status);
                        }
                    }, mockDuration);
                    return;
                } else {
                    const availableMocks = Object.keys(mockData);
                    const errorMsg = `No mock data found for URL`;
                    const suggestion = availableMocks.length > 0 
                        ? `Available mocks: ${availableMocks.slice(0, 5).join(', ')}${availableMocks.length > 5 ? '...' : ''}`
                        : 'No mock data file loaded. Add mock data or switch to REAL mode.';
                    
                    console.log(chalk.yellow(`   ⚠ ${errorMsg}: ${urlStr}`));
                    
                    // Log mock not found error
                    sendHttpLog('error', {
                        id: requestId,
                        type: 'MOCK_NOT_FOUND',
                        message: errorMsg,
                        url: urlStr,
                        suggestion: suggestion,
                        availableMocks: availableMocks,
                        fix: 'Add this URL to your mock JSON file or enable REAL HTTP mode'
                    });
                    
                    if (callback) {
                        callback('{"success": true}', 200);
                    }
                    return;
                }
            }
            
            // Real HTTP request
            const startTime = Date.now();
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 30000);
            
            fetch(urlStr, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...(headers || {})
                },
                body: bodyStr,
                signal: controller.signal
            })
                .then(response => {
                    const status = response.status;
                    const responseHeaders = {};
                    response.headers.forEach((value, key) => {
                        responseHeaders[key] = value;
                    });
                    
                    return response.text().then(data => ({ 
                        data, 
                        status, 
                        headers: responseHeaders,
                        ok: response.ok
                    }));
                })
                .then(({ data, status, headers: responseHeaders, ok }) => {
                    clearTimeout(timeoutId);
                    const duration = Date.now() - startTime;
                    
                    // Log response
                    sendHttpLog('response', {
                        id: requestId,
                        status: status,
                        headers: responseHeaders,
                        body: data,
                        bodyPreview: data.substring(0, 200),
                        mode: 'REAL',
                        duration: duration,
                        ok: ok
                    });
                    
                    if (!ok) {
                        // HTTP error status
                        let errorType = status >= 500 ? 'SERVER_ERROR' : 'CLIENT_ERROR';
                        let suggestion = status === 401 ? 'Authentication failed. Check credentials.' :
                                        status === 403 ? 'Access forbidden. Check permissions.' :
                                        status === 404 ? 'Resource not found. Check URL.' :
                                        status >= 500 ? 'Server error. API may be down.' :
                                        'Client error. Check request parameters.';
                        
                        sendHttpLog('error', {
                            id: requestId,
                            type: errorType,
                            message: `HTTP ${status} ${getStatusText(status)}`,
                            status: status,
                            url: urlStr,
                            body: data,
                            bodyPreview: data.substring(0, 200),
                            suggestion: suggestion,
                            fix: status === 401 ? 'Add/update Authorization header' : 
                                 status === 404 ? 'Verify the API endpoint URL' :
                                 'Check server status and try again'
                        });
                    }
                    
                    console.log(chalk.green(`   ✓ Response: ${status}`));
                    if (callback) {
                        callback(data, status);
                    }
                })
                .catch(e => {
                    clearTimeout(timeoutId);
                    const duration = Date.now() - startTime;
                    let errorType = 'NETWORK_ERROR';
                    let suggestion = '';
                    let fix = '';
                    
                    // Categorize error (same logic as GET)
                    if (e.name === 'AbortError' || e.message.includes('timeout') || e.message.includes('aborted')) {
                        errorType = 'TIMEOUT';
                        suggestion = 'Request timed out. The server may be slow or unreachable.';
                        fix = 'Increase timeout or check network connection';
                    } else if (e.code === 'ENOTFOUND' || e.message.includes('getaddrinfo')) {
                        errorType = 'DNS_ERROR';
                        suggestion = 'DNS lookup failed. The hostname cannot be resolved.';
                        fix = 'Check the URL hostname for typos';
                    } else if (e.code === 'ECONNREFUSED') {
                        errorType = 'CONNECTION_REFUSED';
                        suggestion = 'Connection refused. The server is not accepting connections.';
                        fix = 'Check if the server is running and the port is correct';
                    } else {
                        suggestion = e.message || 'Unknown network error occurred.';
                        fix = 'Check network connection and server availability';
                    }
                    
                    console.log(chalk.red(`   ✗ Error: ${e.message}`));
                    
                    sendHttpLog('error', {
                        id: requestId,
                        type: errorType,
                        message: e.message,
                        code: e.code,
                        url: urlStr,
                        duration: duration,
                        suggestion: suggestion,
                        fix: fix,
                        stack: e.stack
                    });
                    
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


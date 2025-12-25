// AIO Widget Emulator - Main Application

// ============================================================================
// State
// ============================================================================

let editor = null;
let autoResumeEnabled = true;
let autoResumeTimeout = null;
let httpRequestCount = 0;
let httpErrorCount = 0;
let allFolded = false;

// Default settings
const defaultSettings = {
  mikrotik: { ip: '10.1.1.1', user: 'admin', pass: '' },
  tuya: { clientId: '', secret: '' },
  crypto: { apiKey: '' },
  groq: { apiKey: '' },
  autoDelay: 1000
};

// ============================================================================
// Settings Management
// ============================================================================

function getSettings() {
  try {
    const saved = localStorage.getItem('emulatorSettings');
    if (saved) {
      return { ...defaultSettings, ...JSON.parse(saved) };
    }
  } catch (e) {
    console.error('Failed to load settings:', e);
  }
  return { ...defaultSettings };
}

function saveSettings(settings) {
  localStorage.setItem('emulatorSettings', JSON.stringify(settings));
}

function loadSettingsToForm() {
  const settings = getSettings();
  document.getElementById('settingMtIp').value = settings.mikrotik?.ip || '';
  document.getElementById('settingMtUser').value = settings.mikrotik?.user || '';
  document.getElementById('settingMtPass').value = settings.mikrotik?.pass || '';
  document.getElementById('settingTuyaId').value = settings.tuya?.clientId || '';
  document.getElementById('settingTuyaSecret').value = settings.tuya?.secret || '';
  document.getElementById('settingCryptoKey').value = settings.crypto?.apiKey || '';
  document.getElementById('settingGroqKey').value = settings.groq?.apiKey || '';
  document.getElementById('settingAutoDelay').value = settings.autoDelay || 1000;
}

function saveSettingsFromForm() {
  const settings = {
    mikrotik: {
      ip: document.getElementById('settingMtIp').value,
      user: document.getElementById('settingMtUser').value,
      pass: document.getElementById('settingMtPass').value
    },
    tuya: {
      clientId: document.getElementById('settingTuyaId').value,
      secret: document.getElementById('settingTuyaSecret').value
    },
    crypto: {
      apiKey: document.getElementById('settingCryptoKey').value
    },
    groq: {
      apiKey: document.getElementById('settingGroqKey').value
    },
    autoDelay: parseInt(document.getElementById('settingAutoDelay').value) || 1000
  };
  saveSettings(settings);
  showToast('Settings saved', 'success');
  closeSettingsModal();

  // Sync settings to server
  syncSettingsToServer(settings);
}

function resetSettingsForm() {
  saveSettings(defaultSettings);
  loadSettingsToForm();
  showToast('Settings reset to defaults', 'info');
}

function openSettingsModal() {
  loadSettingsToForm();
  document.getElementById('settingsModal').classList.add('show');
}

function closeSettingsModal() {
  document.getElementById('settingsModal').classList.remove('show');
}

async function syncSettingsToServer(settings) {
  try {
    await fetch('/api/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(settings)
    });
  } catch (e) {
    console.error('Failed to sync settings:', e);
  }
}

// ============================================================================
// Monaco Editor Setup
// ============================================================================

require.config({
  paths: { vs: 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs' }
});

require(['vs/editor/editor.main'], function() {
  editor = monaco.editor.create(document.getElementById('editor'), {
    value: getDefaultScript(),
    language: 'lua',
    theme: 'vs-dark',
    automaticLayout: true,
    minimap: { enabled: false },
    fontSize: 13,
    lineNumbers: 'on',
    roundedSelection: false,
    scrollBeyondLastLine: false,
    cursorStyle: 'line',
    folding: true,
    fontFamily: "'Cascadia Code', 'Fira Code', 'Consolas', monospace",
    padding: { top: 8, bottom: 8 },
    scrollbar: {
      verticalScrollbarSize: 10,
      horizontalScrollbarSize: 10
    }
  });

  // Auto-run on content change
  editor.onDidChangeModelContent(() => {
    if (autoResumeEnabled) {
      clearTimeout(autoResumeTimeout);
      autoResumeTimeout = setTimeout(() => executeScript('on_resume'), 1000);
    }
  });

  // Initial execution - wait for both editor AND DOM to be ready
  function runInitialScript() {
    if (editor && document.readyState === 'complete') {
      // Small delay to ensure layout is stable
      setTimeout(() => executeScript('on_resume'), 200);
    } else {
      // Poll until ready
      setTimeout(runInitialScript, 100);
    }
  }

  // Start checking for readiness
  if (document.readyState === 'complete') {
    runInitialScript();
  } else {
    window.addEventListener('load', runInitialScript);
  }
});

function getDefaultScript() {
  return `-- name = "My Widget"
-- description = "Widget description"

function on_resume()
  ui:show_text("Hello from AIO Launcher!")
end

function on_click()
  system:toast("Widget clicked!")
end

function on_long_click()
  ui:show_context_menu({
    "Option 1",
    "Option 2",
    "Cancel"
  }, function(index)
    system:toast("Selected: " .. index)
  end)
end`;
}

// ============================================================================
// Script Execution
// ============================================================================

async function executeScript(functionName = 'on_resume') {
  if (!editor) return;

  const script = editor.getValue();
  const mockFile = document.getElementById('mockSelect').value;

  // Update status
  updateExecStatus('running');
  addConsoleEntry('info', `Executing ${functionName}()...`);

  try {
    // Load mock data if selected
    let mockData = null;
    if (mockFile) {
      const mockResponse = await fetch(`/api/mocks/${mockFile}`);
      mockData = await mockResponse.json();
    }

    const response = await fetch('/api/execute', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ script, functionName, mockData })
    });

    const result = await response.json();

    if (result.success) {
      displayOutput(result.output);
      updateExecStatus('success');

      // Process HTTP logs
      if (result.httpLogs && result.httpLogs.length > 0) {
        clearHttpLogEmpty();
        result.httpLogs
          .sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp))
          .forEach(log => addHttpLogEntry(log));
      }

      if (!result.functionExists) {
        addConsoleEntry('warning', `Function ${functionName}() not found`);
      } else {
        addConsoleEntry('success', `${functionName}() completed`);
      }
    } else {
      displayError(result.error);
      updateExecStatus('error');
      addConsoleEntry('error', `Error: ${result.error}`);

      // Show error details in console
      if (result.luaError) {
        addConsoleEntry('error', `Lua: ${result.luaError}`);
      }
    }

    // Update last execution time
    document.getElementById('lastExecTime').textContent =
      `Last run: ${new Date().toLocaleTimeString()}`;

  } catch (error) {
    console.error('Execution error:', error);
    displayError(error.message);
    updateExecStatus('error');
    addConsoleEntry('error', `Request failed: ${error.message}`);
  }
}

function updateExecStatus(status) {
  const badge = document.getElementById('execStatus');
  badge.className = 'badge';

  switch (status) {
    case 'running':
      badge.textContent = 'Running...';
      break;
    case 'success':
      badge.textContent = 'Success';
      badge.classList.add('success');
      break;
    case 'error':
      badge.textContent = 'Error';
      badge.classList.add('error');
      break;
    default:
      badge.textContent = 'Ready';
  }
}

// ============================================================================
// Output Display
// ============================================================================

function displayOutput(output) {
  const container = document.getElementById('widgetOutput');

  if (!output || (typeof output === 'string' && output.trim() === '')) {
    container.innerHTML = `
      <div class="widget-placeholder">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
          <circle cx="12" cy="12" r="10"/>
          <line x1="12" y1="8" x2="12" y2="12"/>
          <line x1="12" y1="16" x2="12.01" y2="16"/>
        </svg>
        <p>No output from widget</p>
      </div>
    `;
    return;
  }

  const outputStr = typeof output === 'string' ? output : String(output);
  container.innerHTML = escapeHtml(outputStr).replace(/\n/g, '<br>');
}

function displayError(error) {
  const container = document.getElementById('widgetOutput');
  container.innerHTML = `
    <div class="widget-placeholder" style="color: var(--error);">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
        <circle cx="12" cy="12" r="10"/>
        <line x1="15" y1="9" x2="9" y2="15"/>
        <line x1="9" y1="9" x2="15" y2="15"/>
      </svg>
      <p>${escapeHtml(error)}</p>
    </div>
  `;
}

// ============================================================================
// HTTP Log Display
// ============================================================================

function clearHttpLogEmpty() {
  const log = document.getElementById('httpLog');
  const empty = log.querySelector('.log-empty');
  if (empty) empty.remove();
}

function addHttpLogEntry(log) {
  const httpLog = document.getElementById('httpLog');
  const entry = document.createElement('div');

  // Determine entry type and status
  const isRequest = log.type === 'request';
  const isError = log.type === 'error';
  const isSuccess = log.type === 'response' && log.status >= 200 && log.status < 300;

  entry.className = `http-entry${isError ? ' error' : isSuccess ? ' success' : ''}`;

  // Build header content based on log type
  let headerContent = '';
  const time = new Date(log.timestamp || Date.now()).toLocaleTimeString();

  if (log.type === 'request') {
    const method = (log.method || 'GET').toUpperCase();
    headerContent = `
      <span class="http-method ${method.toLowerCase()}">${method}</span>
      <span class="http-url">${escapeHtml(log.url || '')}</span>
      <span class="http-time">${time}</span>
      <span class="http-duration">${log.mode || 'MOCK'}</span>
    `;
    httpRequestCount++;
  } else if (log.type === 'response') {
    const statusClass = log.status >= 200 && log.status < 300 ? 'success' :
                        log.status >= 400 ? 'error' : 'warning';
    headerContent = `
      <span class="http-status ${statusClass}">${log.status} ${getStatusText(log.status)}</span>
      <span class="http-url">${log.mode || 'MOCK'}</span>
      <span class="http-time">${time}</span>
      <span class="http-duration">${log.duration || 0}ms</span>
    `;
  } else if (log.type === 'error') {
    headerContent = `
      <span class="http-status error">${log.type || 'ERROR'}</span>
      <span class="http-url">${escapeHtml(log.message || 'Unknown error')}</span>
      <span class="http-time">${time}</span>
    `;
    httpErrorCount++;
  }

  // Build body content
  let bodyContent = buildHttpBody(log);

  entry.innerHTML = `
    <div class="http-entry-header">
      <svg class="http-fold" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="6 9 12 15 18 9"/>
      </svg>
      ${headerContent}
    </div>
    <div class="http-entry-body">
      ${bodyContent}
    </div>
  `;

  // Collapse successful responses by default
  if (log.type === 'response' && log.status >= 200 && log.status < 300) {
    entry.classList.add('collapsed');
  }

  // Click to toggle
  entry.querySelector('.http-entry-header').addEventListener('click', () => {
    entry.classList.toggle('collapsed');
  });

  // Insert at top
  httpLog.insertBefore(entry, httpLog.firstChild);

  // Update badge and status bar
  updateHttpBadge();
  updateStatusBar();

  // Limit entries
  while (httpLog.children.length > 100) {
    httpLog.removeChild(httpLog.lastChild);
  }
}

function buildHttpBody(log) {
  let html = '';

  if (log.type === 'request') {
    // Request details
    html += buildSection('Request URL', log.url);

    if (log.headers && Object.keys(log.headers).length > 0) {
      html += buildSection('Request Headers', JSON.stringify(log.headers, null, 2));
    } else {
      html += buildSection('Request Headers', '(none)');
    }

    if (log.body) {
      html += buildSection('Request Body', log.body);
    }

  } else if (log.type === 'response') {
    // Response details
    html += buildSection('Status', `${log.status} ${getStatusText(log.status)}`);
    html += buildSection('Duration', `${log.duration || 0}ms`);
    html += buildSection('Mode', log.mode || 'UNKNOWN');

    if (log.headers && Object.keys(log.headers).length > 0) {
      html += buildSection('Response Headers', JSON.stringify(log.headers, null, 2));
    }

    if (log.body) {
      const bodyPreview = log.body.length > 2000
        ? log.body.substring(0, 2000) + '\n... (truncated)'
        : log.body;
      html += buildSection('Response Body', bodyPreview);
    }

  } else if (log.type === 'error') {
    // Error details
    html += buildSection('Error Type', log.type || 'UNKNOWN');
    html += buildSection('Message', log.message || 'Unknown error');

    if (log.url) {
      html += buildSection('Request URL', log.url);
    }

    if (log.status) {
      html += buildSection('HTTP Status', `${log.status} ${getStatusText(log.status)}`);
    }

    if (log.requestHeaders && Object.keys(log.requestHeaders).length > 0) {
      html += buildSection('Request Headers Sent', JSON.stringify(log.requestHeaders, null, 2));
    }

    if (log.suggestion) {
      html += `
        <div class="http-suggestion">
          <div class="http-suggestion-title">What Happened</div>
          <div class="http-suggestion-text">${escapeHtml(log.suggestion)}</div>
        </div>
      `;
    }

    if (log.fix) {
      html += `
        <div class="http-fix">
          <div class="http-fix-title">How to Fix</div>
          <div class="http-fix-text">${escapeHtml(log.fix)}</div>
        </div>
      `;
    }

    if (log.availableMocks && log.availableMocks.length > 0) {
      const mockList = log.availableMocks.slice(0, 10).join('\n');
      html += buildSection('Available Mocks', mockList);
    }

    if (log.body || log.bodyPreview) {
      html += buildSection('Response Body', log.bodyPreview || log.body);
    }
  }

  return html;
}

function buildSection(title, content) {
  return `
    <div class="http-section">
      <div class="http-section-title">${escapeHtml(title)}</div>
      <div class="http-section-content"><pre>${escapeHtml(content || '')}</pre></div>
    </div>
  `;
}

function updateHttpBadge() {
  document.getElementById('httpBadge').textContent = httpRequestCount;
}

function updateStatusBar() {
  document.getElementById('errorCount').textContent =
    `${httpErrorCount} error${httpErrorCount !== 1 ? 's' : ''}`;
  document.getElementById('requestCount').textContent =
    `${httpRequestCount} request${httpRequestCount !== 1 ? 's' : ''}`;
}

// ============================================================================
// Console Log
// ============================================================================

function addConsoleEntry(type, message) {
  const consoleLog = document.getElementById('consoleLog');

  // Remove empty placeholder
  const empty = consoleLog.querySelector('.log-empty');
  if (empty) empty.remove();

  const entry = document.createElement('div');
  entry.className = `console-entry ${type}`;

  const time = new Date().toLocaleTimeString();
  entry.innerHTML = `
    <span class="console-time">${time}</span>
    <span class="console-msg">${escapeHtml(message)}</span>
  `;

  consoleLog.appendChild(entry);

  // Auto-scroll
  consoleLog.scrollTop = consoleLog.scrollHeight;

  // Limit entries
  while (consoleLog.children.length > 200) {
    consoleLog.removeChild(consoleLog.firstChild);
  }
}

// ============================================================================
// Storage View
// ============================================================================

async function refreshStorage() {
  try {
    const response = await fetch('/api/storage');
    const data = await response.json();

    const storageView = document.getElementById('storageView');

    if (!data || Object.keys(data).length === 0) {
      storageView.innerHTML = `
        <div class="log-empty">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
            <ellipse cx="12" cy="5" rx="9" ry="3"/>
            <path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/>
            <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>
          </svg>
          <span>Storage is empty</span>
          <small>Use storage:put() in your widget</small>
        </div>
      `;
      return;
    }

    storageView.innerHTML = Object.entries(data)
      .map(([key, value]) => `
        <div class="storage-item">
          <span class="storage-key">${escapeHtml(key)}</span>
          <span class="storage-value">${escapeHtml(typeof value === 'object' ? JSON.stringify(value) : String(value))}</span>
        </div>
      `)
      .join('');

  } catch (error) {
    console.error('Failed to load storage:', error);
  }
}

async function clearStorage() {
  if (!confirm('Clear all widget storage?')) return;

  try {
    await fetch('/api/storage', { method: 'DELETE' });
    refreshStorage();
    addConsoleEntry('info', 'Storage cleared');
  } catch (error) {
    console.error('Failed to clear storage:', error);
  }
}

// ============================================================================
// Widget & Mock Loading
// ============================================================================

async function loadWidgets() {
  try {
    const response = await fetch('/api/widgets');
    const widgets = await response.json();

    const select = document.getElementById('widgetSelect');
    select.innerHTML = '<option value="">Load Widget...</option>';

    widgets.forEach(widget => {
      const option = document.createElement('option');
      option.value = widget.path;
      option.textContent = widget.name;
      select.appendChild(option);
    });
  } catch (error) {
    console.error('Failed to load widgets:', error);
    addConsoleEntry('error', 'Failed to load widget list');
  }
}

async function loadWidget(path) {
  if (!path) return;

  try {
    const response = await fetch(`/api/widgets/load?path=${encodeURIComponent(path)}`);
    const data = await response.json();

    if (data.content && editor) {
      editor.setValue(data.content);
      const name = path.split(/[/\\]/).pop();
      addConsoleEntry('success', `Loaded: ${name}`);
    }
  } catch (error) {
    console.error('Failed to load widget:', error);
    addConsoleEntry('error', 'Failed to load widget');
  }
}

async function deleteWidget() {
  const select = document.getElementById('widgetSelect');
  const selected = select.value;
  if (!selected) {
    showToast('No widget selected', 'warning');
    return;
  }

  // Extract widget name from path
  const pathParts = selected.split(/[/\\]/);
  const fileName = pathParts.pop();
  const widgetName = fileName.replace('.lua', '');

  if (!confirm(`Delete widget "${widgetName}"?\n\nThis cannot be undone.`)) {
    return;
  }

  try {
    const response = await fetch(`/api/widgets/${encodeURIComponent(widgetName)}`, {
      method: 'DELETE'
    });

    if (response.ok) {
      addConsoleEntry('success', `Deleted: ${widgetName}`);
      showToast('Widget deleted', 'success');
      editor.setValue('');
      select.value = '';
      loadWidgets(); // Reload widget list
    } else {
      const error = await response.json();
      addConsoleEntry('error', `Delete failed: ${error.error}`);
      showToast('Failed to delete', 'error');
    }
  } catch (err) {
    addConsoleEntry('error', `Delete failed: ${err.message}`);
    showToast('Failed to delete', 'error');
  }
}

async function loadMocks() {
  try {
    const response = await fetch('/api/mocks');
    const mocks = await response.json();

    const select = document.getElementById('mockSelect');
    select.innerHTML = '<option value="">No Mocks</option>';

    mocks.forEach(mock => {
      const option = document.createElement('option');
      option.value = mock.name;
      option.textContent = mock.name.replace('.json', '');
      select.appendChild(option);
    });
  } catch (error) {
    console.error('Failed to load mocks:', error);
  }
}

// ============================================================================
// HTTP Mode
// ============================================================================

async function setHttpMode(isReal) {
  try {
    const mode = isReal ? 'real' : 'mock';
    await fetch('/api/http-mode', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mode })
    });

    // Update visual indicator
    const label = document.getElementById('httpModeLabel');
    const toggle = document.getElementById('httpModeToggle');
    label.textContent = isReal ? 'Real' : 'Mock';
    label.className = isReal ? 'http-mode-real' : 'http-mode-mock';

    // Save to localStorage
    localStorage.setItem('httpMode', mode);

    // Show toast notification
    showToast(`HTTP Mode: ${mode.toUpperCase()}`, isReal ? 'success' : 'warning');

    addConsoleEntry('info', `HTTP mode: ${mode.toUpperCase()}`);
  } catch (error) {
    console.error('Failed to set HTTP mode:', error);
  }
}

// Load saved HTTP mode on startup
function loadHttpMode() {
  const savedMode = localStorage.getItem('httpMode') || 'mock';
  const isReal = savedMode === 'real';
  const toggle = document.getElementById('httpModeToggle');
  const label = document.getElementById('httpModeLabel');

  toggle.checked = isReal;
  label.textContent = isReal ? 'Real' : 'Mock';
  label.className = isReal ? 'http-mode-real' : 'http-mode-mock';

  // Set server mode without toast
  fetch('/api/http-mode', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ mode: savedMode })
  }).catch(err => console.error('Failed to sync HTTP mode:', err));
}

// Toast notification
function showToast(message, type = 'info') {
  // Remove existing toast
  const existing = document.querySelector('.toast');
  if (existing) existing.remove();

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  document.body.appendChild(toast);

  // Animate in
  setTimeout(() => toast.classList.add('show'), 10);

  // Remove after delay
  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, 2000);
}

// ============================================================================
// File Upload / Drag & Drop
// ============================================================================

function setupFileUpload() {
  const dropZone = document.getElementById('dropZone');
  const editorPanel = document.getElementById('editorPanel');
  const fileInput = document.getElementById('fileInput');
  const uploadBtn = document.getElementById('uploadBtn');

  // Click upload button
  uploadBtn.addEventListener('click', () => fileInput.click());

  // File input change
  fileInput.addEventListener('change', (e) => {
    if (e.target.files.length > 0) {
      handleFile(e.target.files[0]);
    }
  });

  // Drag events
  let dragCounter = 0;

  editorPanel.addEventListener('dragenter', (e) => {
    e.preventDefault();
    dragCounter++;
    dropZone.classList.add('active');
  });

  editorPanel.addEventListener('dragleave', (e) => {
    e.preventDefault();
    dragCounter--;
    if (dragCounter === 0) {
      dropZone.classList.remove('active');
    }
  });

  editorPanel.addEventListener('dragover', (e) => {
    e.preventDefault();
  });

  editorPanel.addEventListener('drop', (e) => {
    e.preventDefault();
    dragCounter = 0;
    dropZone.classList.remove('active');

    if (e.dataTransfer.files.length > 0) {
      handleFile(e.dataTransfer.files[0]);
    }
  });
}

async function handleFile(file) {
  if (!file.name.endsWith('.lua')) {
    addConsoleEntry('warning', 'Please upload a .lua file');
    return;
  }

  const reader = new FileReader();
  reader.onload = async (e) => {
    const content = e.target.result;

    // Load into editor
    if (editor) {
      editor.setValue(content);
    }

    // Save to server to persist in widget list
    try {
      const filename = file.name.replace('.lua', '');
      const response = await fetch('/api/widgets/upload', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ filename, content })
      });

      if (response.ok) {
        const result = await response.json();
        addConsoleEntry('success', `Saved: ${file.name}`);
        showToast(`Widget "${result.name}" saved`, 'success');
        loadWidgets(); // Reload widget list to show new file
      } else {
        const error = await response.json();
        addConsoleEntry('error', `Failed to save: ${error.error}`);
      }
    } catch (err) {
      addConsoleEntry('error', `Failed to save: ${err.message}`);
    }
  };
  reader.onerror = () => {
    addConsoleEntry('error', 'Failed to read file');
  };
  reader.readAsText(file);
}

// ============================================================================
// Tab Navigation
// ============================================================================

function setupTabs() {
  const tabs = document.querySelectorAll('.tab-btn');
  const contents = document.querySelectorAll('.tab-content');

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const target = tab.dataset.tab;

      // Update active tab
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');

      // Show target content
      contents.forEach(c => {
        c.classList.toggle('active', c.id === `${target}Tab`);
      });

      // Refresh storage when switching to storage tab
      if (target === 'storage') {
        refreshStorage();
      }
    });
  });
}

// ============================================================================
// Utilities
// ============================================================================

function escapeHtml(text) {
  if (text === null || text === undefined) return '';
  const div = document.createElement('div');
  div.textContent = String(text);
  return div.innerHTML;
}

function getStatusText(status) {
  const texts = {
    200: 'OK', 201: 'Created', 204: 'No Content',
    301: 'Moved', 302: 'Found', 304: 'Not Modified',
    400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden',
    404: 'Not Found', 408: 'Timeout', 429: 'Too Many Requests',
    500: 'Server Error', 502: 'Bad Gateway', 503: 'Unavailable', 504: 'Gateway Timeout'
  };
  return texts[status] || '';
}

// ============================================================================
// Event Listeners
// ============================================================================

document.addEventListener('DOMContentLoaded', () => {
  // Load data
  loadWidgets();
  loadMocks();
  loadHttpMode();

  // Setup features
  setupTabs();
  setupFileUpload();

  // Widget selector
  document.getElementById('widgetSelect').addEventListener('change', (e) => {
    loadWidget(e.target.value);
  });

  // Delete widget button
  document.getElementById('deleteWidgetBtn').addEventListener('click', deleteWidget);

  // Mock selector
  document.getElementById('mockSelect').addEventListener('change', () => {
    if (autoResumeEnabled) {
      executeScript('on_resume');
    }
  });

  // HTTP mode toggle
  document.getElementById('httpModeToggle').addEventListener('change', (e) => {
    setHttpMode(e.target.checked);
  });

  // Auto resume toggle
  document.getElementById('autoResumeToggle').addEventListener('change', (e) => {
    autoResumeEnabled = e.target.checked;
    addConsoleEntry('info', `Auto-run: ${autoResumeEnabled ? 'ON' : 'OFF'}`);
  });

  // Control buttons
  document.getElementById('onResumeBtn').addEventListener('click', () => {
    executeScript('on_resume');
  });

  document.getElementById('onClickBtn').addEventListener('click', () => {
    executeScript('on_click');
  });

  document.getElementById('onLongClickBtn').addEventListener('click', () => {
    executeScript('on_long_click');
  });

  // Editor controls
  document.getElementById('clearBtn').addEventListener('click', () => {
    if (confirm('Clear editor content?')) {
      editor.setValue('');
    }
  });

  document.getElementById('saveBtn').addEventListener('click', () => {
    const content = editor.getValue();
    const blob = new Blob([content], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'widget.lua';
    a.click();
    URL.revokeObjectURL(url);
    addConsoleEntry('success', 'Script saved');
  });

  // Log controls - context-aware clear button
  document.getElementById('clearLogBtn').addEventListener('click', () => {
    const activeTab = document.querySelector('.tab-btn.active').dataset.tab;

    if (activeTab === 'http') {
      const httpLog = document.getElementById('httpLog');
      httpLog.innerHTML = `
        <div class="log-empty">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
            <circle cx="12" cy="12" r="10"/>
            <line x1="12" y1="8" x2="12" y2="12"/>
            <line x1="12" y1="16" x2="12.01" y2="16"/>
          </svg>
          <span>No HTTP requests yet</span>
          <small>Run your script to see network activity</small>
        </div>
      `;
      httpRequestCount = 0;
      httpErrorCount = 0;
      updateHttpBadge();
      updateStatusBar();
    } else if (activeTab === 'console') {
      const consoleLog = document.getElementById('consoleLog');
      consoleLog.innerHTML = `
        <div class="log-empty">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
            <polyline points="4 17 10 11 4 5"/>
            <line x1="12" y1="19" x2="20" y2="19"/>
          </svg>
          <span>Console output</span>
          <small>System messages will appear here</small>
        </div>
      `;
    } else if (activeTab === 'storage') {
      // Refresh storage view to show current state
      refreshStorage();
    }
  });

  document.getElementById('foldAllBtn').addEventListener('click', () => {
    const entries = document.querySelectorAll('.http-entry');
    entries.forEach(entry => {
      if (allFolded) {
        entry.classList.remove('collapsed');
      } else {
        entry.classList.add('collapsed');
      }
    });
    allFolded = !allFolded;
    document.getElementById('foldAllBtn').textContent = allFolded ? 'Unfold' : 'Fold';
  });

  // Storage controls
  document.getElementById('refreshStorageBtn').addEventListener('click', refreshStorage);
  document.getElementById('clearStorageBtn').addEventListener('click', clearStorage);

  // Settings modal
  document.getElementById('settingsBtn').addEventListener('click', openSettingsModal);
  document.getElementById('closeSettings').addEventListener('click', closeSettingsModal);
  document.getElementById('saveSettings').addEventListener('click', saveSettingsFromForm);
  document.getElementById('resetSettings').addEventListener('click', resetSettingsForm);

  // Close modal on overlay click
  document.getElementById('settingsModal').addEventListener('click', (e) => {
    if (e.target.id === 'settingsModal') {
      closeSettingsModal();
    }
  });

  // Close modal on Escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      closeSettingsModal();
    }
  });

  // Editor collapse - proper hide/show with expand button
  document.getElementById('collapseEditorBtn').addEventListener('click', () => {
    const editorPanel = document.getElementById('editorPanel');
    const expandBtn = document.getElementById('expandEditorBtn');

    editorPanel.classList.add('collapsed');
    expandBtn.classList.remove('hidden');
    localStorage.setItem('editorCollapsed', 'true');

    // Trigger Monaco resize after transition
    setTimeout(() => {
      if (editor) editor.layout();
    }, 350);
  });

  // Expand editor button
  document.getElementById('expandEditorBtn').addEventListener('click', () => {
    const editorPanel = document.getElementById('editorPanel');
    const expandBtn = document.getElementById('expandEditorBtn');

    editorPanel.classList.remove('collapsed');
    expandBtn.classList.add('hidden');
    localStorage.setItem('editorCollapsed', 'false');

    // Trigger Monaco resize after transition
    setTimeout(() => {
      if (editor) editor.layout();
    }, 350);
  });

  // Debug panel minimize/expand toggle
  document.getElementById('toggleDebugBtn').addEventListener('click', () => {
    const debugPanel = document.getElementById('debugPanel');
    const isMinimized = debugPanel.classList.toggle('minimized');

    // Rotate icon
    const icon = document.querySelector('#toggleDebugBtn svg');
    icon.style.transform = isMinimized ? 'rotate(180deg)' : '';

    localStorage.setItem('debugMinimized', isMinimized ? 'true' : 'false');
  });

  // Restore layout states on load
  restoreLayoutStates();

  // Keyboard shortcuts
  document.addEventListener('keydown', (e) => {
    // Ctrl/Cmd + Enter: Execute
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      executeScript('on_resume');
    }
    // Ctrl/Cmd + S: Save
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      document.getElementById('saveBtn').click();
    }
  });
});

// ============================================================================
// Layout State Restoration
// ============================================================================

function restoreLayoutStates() {
  // Restore editor collapsed state
  if (localStorage.getItem('editorCollapsed') === 'true') {
    const editorPanel = document.getElementById('editorPanel');
    const expandBtn = document.getElementById('expandEditorBtn');
    if (editorPanel && expandBtn) {
      editorPanel.classList.add('collapsed');
      expandBtn.classList.remove('hidden');
    }
  }

  // Restore debug panel minimized state
  if (localStorage.getItem('debugMinimized') === 'true') {
    const debugPanel = document.getElementById('debugPanel');
    const icon = document.querySelector('#toggleDebugBtn svg');
    if (debugPanel) {
      debugPanel.classList.add('minimized');
      if (icon) icon.style.transform = 'rotate(180deg)';
    }
  }
}

// ============================================================================
// MikroTik Monitor
// ============================================================================

let monitorInterval = null;
let speedHistory = { dl: [], ul: [], times: [] };
const MAX_SPEED_POINTS = 60;

async function fetchMikroTikUsers() {
  try {
    const response = await fetch('/api/mikrotik/users');
    const data = await response.json();

    const userList = document.getElementById('userList');
    const userCount = document.getElementById('userCount');

    if (data.error) {
      userList.innerHTML = `<div class="log-empty small"><span>${escapeHtml(data.error)}</span></div>`;
      userCount.textContent = '-';
      return;
    }

    const users = data.users || [];
    userCount.textContent = users.length;

    if (users.length === 0) {
      userList.innerHTML = '<div class="log-empty small"><span>No active users</span></div>';
      return;
    }

    userList.innerHTML = users.slice(0, 20).map(user => `
      <div class="user-item">
        <span class="user-name">${escapeHtml(user.user || user.name || 'Unknown')}</span>
        <span class="user-ip">${escapeHtml(user.address || user['caller-id'] || '-')}</span>
      </div>
    `).join('');
  } catch (error) {
    document.getElementById('userList').innerHTML =
      `<div class="log-empty small"><span>Error: ${escapeHtml(error.message)}</span></div>`;
    document.getElementById('userCount').textContent = '-';
  }
}

async function fetchMikroTikInterfaces() {
  try {
    const response = await fetch('/api/mikrotik/interfaces');
    const interfaces = await response.json();

    const interfaceList = document.getElementById('interfaceList');
    const interfaceSelect = document.getElementById('monitorInterface');

    if (interfaces.error) {
      interfaceList.innerHTML = `<div class="log-empty small"><span>${escapeHtml(interfaces.error)}</span></div>`;
      return;
    }

    if (!Array.isArray(interfaces) || interfaces.length === 0) {
      interfaceList.innerHTML = '<div class="log-empty small"><span>No interfaces found</span></div>';
      return;
    }

    // Update interface list display
    interfaceList.innerHTML = interfaces.slice(0, 10).map(iface => `
      <div class="interface-item">
        <span class="iface-name">${escapeHtml(iface.name || '-')}</span>
        <span class="iface-status ${iface.running ? 'up' : 'down'}">${iface.running ? 'UP' : 'DOWN'}</span>
      </div>
    `).join('');

    // Update interface selector
    interfaceSelect.innerHTML = interfaces
      .filter(i => i.type === 'ether' || i.type === 'pppoe-out' || i.type === 'bridge')
      .map(iface => `<option value="${escapeHtml(iface.name)}">${escapeHtml(iface.name)}</option>`)
      .join('');
  } catch (error) {
    document.getElementById('interfaceList').innerHTML =
      `<div class="log-empty small"><span>Error: ${escapeHtml(error.message)}</span></div>`;
  }
}

async function fetchTrafficStats() {
  try {
    const iface = document.getElementById('monitorInterface').value;
    const response = await fetch(`/api/mikrotik/traffic?iface=${encodeURIComponent(iface)}`);
    const data = await response.json();

    if (data.error) {
      return;
    }

    // Parse traffic data (values are in bytes/sec)
    let rxBps = 0, txBps = 0;

    if (Array.isArray(data) && data.length > 0) {
      rxBps = parseInt(data[0]['rx-bits-per-second'] || 0) / 1000000;
      txBps = parseInt(data[0]['tx-bits-per-second'] || 0) / 1000000;
    } else if (data['rx-byte']) {
      // Fallback to interface stats
      rxBps = parseInt(data['rx-byte'] || 0) / 1000000;
      txBps = parseInt(data['tx-byte'] || 0) / 1000000;
    }

    // Update speed display
    document.getElementById('dlSpeed').textContent = rxBps.toFixed(2) + ' Mbps';
    document.getElementById('ulSpeed').textContent = txBps.toFixed(2) + ' Mbps';

    // Add to history
    speedHistory.dl.push(rxBps);
    speedHistory.ul.push(txBps);
    speedHistory.times.push(new Date());

    // Limit history
    if (speedHistory.dl.length > MAX_SPEED_POINTS) {
      speedHistory.dl.shift();
      speedHistory.ul.shift();
      speedHistory.times.shift();
    }

    // Draw chart
    drawSpeedChart();
  } catch (error) {
    console.error('Traffic fetch error:', error);
  }
}

function drawSpeedChart() {
  const canvas = document.getElementById('speedChart');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  const width = canvas.width;
  const height = canvas.height;

  // Clear
  ctx.fillStyle = '#1e1e1e';
  ctx.fillRect(0, 0, width, height);

  if (speedHistory.dl.length < 2) return;

  // Find max value for scaling
  const maxVal = Math.max(
    Math.max(...speedHistory.dl),
    Math.max(...speedHistory.ul),
    1
  );

  const padding = 10;
  const chartWidth = width - padding * 2;
  const chartHeight = height - padding * 2;

  // Draw download line (green)
  ctx.beginPath();
  ctx.strokeStyle = '#4ec9b0';
  ctx.lineWidth = 2;
  speedHistory.dl.forEach((val, i) => {
    const x = padding + (i / (MAX_SPEED_POINTS - 1)) * chartWidth;
    const y = height - padding - (val / maxVal) * chartHeight;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();

  // Draw upload line (purple)
  ctx.beginPath();
  ctx.strokeStyle = '#c678dd';
  ctx.lineWidth = 2;
  speedHistory.ul.forEach((val, i) => {
    const x = padding + (i / (MAX_SPEED_POINTS - 1)) * chartWidth;
    const y = height - padding - (val / maxVal) * chartHeight;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();

  // Draw max value label
  ctx.fillStyle = '#6d6d6d';
  ctx.font = '10px monospace';
  ctx.fillText(maxVal.toFixed(1) + ' Mbps', padding, padding + 10);
}

function startMonitoring() {
  if (monitorInterval) return;

  monitorInterval = setInterval(fetchTrafficStats, 1000);
  document.getElementById('startMonitor').disabled = true;
  document.getElementById('stopMonitor').disabled = false;
  showToast('Monitoring started', 'success');
}

function stopMonitoring() {
  if (monitorInterval) {
    clearInterval(monitorInterval);
    monitorInterval = null;
  }
  document.getElementById('startMonitor').disabled = false;
  document.getElementById('stopMonitor').disabled = true;
  showToast('Monitoring stopped', 'info');
}

function refreshMonitorData() {
  fetchMikroTikUsers();
  fetchMikroTikInterfaces();
  fetchTrafficStats();
}

// Setup monitor tab events
document.addEventListener('DOMContentLoaded', () => {
  // Monitor tab events (delayed to ensure elements exist)
  setTimeout(() => {
    const startBtn = document.getElementById('startMonitor');
    const stopBtn = document.getElementById('stopMonitor');
    const refreshBtn = document.getElementById('refreshMonitor');

    if (startBtn) startBtn.addEventListener('click', startMonitoring);
    if (stopBtn) stopBtn.addEventListener('click', stopMonitoring);
    if (refreshBtn) refreshBtn.addEventListener('click', refreshMonitorData);

    // Load monitor data when tab is selected
    document.querySelectorAll('.tab-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        if (btn.dataset.tab === 'monitor') {
          refreshMonitorData();
        }
      });
    });
  }, 100);

  // Mobile navigation
  setupMobileNav();
});

// ============================================================================
// Mobile Navigation
// ============================================================================

function setupMobileNav() {
  const mobileNav = document.querySelector('.mobile-nav');
  const mobileNavBtns = document.querySelectorAll('.mobile-nav-btn');
  const panels = {
    editor: document.getElementById('editorPanel'),
    preview: document.getElementById('previewPanel'),
    debug: document.getElementById('debugPanel')
  };

  let activePanel = 'preview';

  // Check if mobile view
  function isMobile() {
    return window.innerWidth <= 768;
  }

  // Set active panel
  function setActivePanel(panelName) {
    activePanel = panelName;

    // Update nav buttons
    mobileNavBtns.forEach(btn => {
      btn.classList.toggle('active', btn.dataset.panel === panelName);
    });

    // Update panels - in mobile, panels slide in/out
    Object.entries(panels).forEach(([name, panel]) => {
      if (panel) {
        if (name === panelName) {
          panel.classList.add('mobile-active');
        } else {
          panel.classList.remove('mobile-active');
        }
      }
    });

    // Resize Monaco editor when switching to editor
    if (panelName === 'editor' && editor) {
      setTimeout(() => editor.layout(), 350);
    }
  }

  // Handle nav button clicks
  mobileNavBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const panelName = btn.dataset.panel;

      // Toggle behavior - clicking active panel again hides it (except preview)
      if (panelName === activePanel && panelName !== 'preview') {
        setActivePanel('preview');
      } else {
        setActivePanel(panelName);
      }
    });
  });

  // Handle resize - show/hide mobile nav
  function handleResize() {
    if (isMobile()) {
      mobileNav.style.display = 'flex';
      // Set initial active panel to preview
      if (!document.querySelector('.panel.mobile-active')) {
        setActivePanel('preview');
      }
    } else {
      mobileNav.style.display = 'none';
      // Remove mobile-active from all panels on desktop
      Object.values(panels).forEach(panel => {
        if (panel) panel.classList.remove('mobile-active');
      });
    }
  }

  window.addEventListener('resize', handleResize);
  handleResize(); // Initial check
}

// ============================================================================
// Initialization Complete
// ============================================================================

console.log('AIO Widget Emulator initialized');
console.log('Shortcuts: Ctrl+Enter = Run, Ctrl+S = Save');

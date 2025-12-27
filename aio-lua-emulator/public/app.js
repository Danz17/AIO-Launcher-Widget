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
  document.getElementById('settingGroqKey').value = settings.groq?.apiKey || '';
  document.getElementById('settingAutoDelay').value = settings.autoDelay || 1000;
}

function saveSettingsFromForm() {
  const settings = {
    groq: {
      apiKey: document.getElementById('settingGroqKey').value
    },
    autoDelay: parseInt(document.getElementById('settingAutoDelay').value) || 1000
  };
  saveSettings(settings);
  showToast('Settings saved', 'success');
  closeSettingsModal();
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

  // Expose editor globally for deploy function
  window.editor = editor;

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

  document.getElementById('onAlarmBtn').addEventListener('click', () => {
    executeScript('on_alarm');
  });

  // Widget size selector
  const widgetSizeSelect = document.getElementById('widgetSize');
  const widgetCard = document.querySelector('.widget-card');

  // Load saved size preference
  const savedSize = localStorage.getItem('widgetSize');
  if (savedSize) {
    widgetSizeSelect.value = savedSize;
    widgetCard.style.setProperty('--widget-width', savedSize + 'px');
  }

  widgetSizeSelect.addEventListener('change', (e) => {
    const size = e.target.value;
    widgetCard.style.setProperty('--widget-width', size + 'px');
    localStorage.setItem('widgetSize', size);
  });

  // Theme toggle
  const themeToggleBtn = document.getElementById('themeToggleBtn');
  const themeIconDark = themeToggleBtn.querySelector('.theme-icon-dark');
  const themeIconLight = themeToggleBtn.querySelector('.theme-icon-light');

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
    if (theme === 'light') {
      themeIconDark.style.display = 'none';
      themeIconLight.style.display = 'block';
    } else {
      themeIconDark.style.display = 'block';
      themeIconLight.style.display = 'none';
    }
  }

  // Load saved theme
  const savedTheme = localStorage.getItem('theme') || 'dark';
  setTheme(savedTheme);

  themeToggleBtn.addEventListener('click', () => {
    const currentTheme = document.documentElement.getAttribute('data-theme') || 'dark';
    setTheme(currentTheme === 'dark' ? 'light' : 'dark');
  });

  // Mock data handling
  const mockDefaults = {
    batteryLevel: 85,
    batteryCharging: false,
    batteryTemp: 25,
    wifiSignal: -45,
    wifiSsid: 'EmulatorWiFi',
    netConnected: true,
    deviceModel: 'Emulator',
    osVersion: '14',
    brightness: 80
  };

  function loadMockData() {
    const saved = localStorage.getItem('mockData');
    const data = saved ? JSON.parse(saved) : mockDefaults;

    document.getElementById('mockBatteryLevel').value = data.batteryLevel;
    document.getElementById('mockBatteryCharging').checked = data.batteryCharging;
    document.getElementById('mockBatteryTemp').value = data.batteryTemp;
    document.getElementById('mockWifiSignal').value = data.wifiSignal;
    document.getElementById('mockWifiSsid').value = data.wifiSsid;
    document.getElementById('mockNetConnected').checked = data.netConnected;
    document.getElementById('mockDeviceModel').value = data.deviceModel;
    document.getElementById('mockOsVersion').value = data.osVersion;
    document.getElementById('mockBrightness').value = data.brightness;

    return data;
  }

  function getMockData() {
    return {
      batteryLevel: parseInt(document.getElementById('mockBatteryLevel').value) || 85,
      batteryCharging: document.getElementById('mockBatteryCharging').checked,
      batteryTemp: parseInt(document.getElementById('mockBatteryTemp').value) || 25,
      wifiSignal: parseInt(document.getElementById('mockWifiSignal').value) || -45,
      wifiSsid: document.getElementById('mockWifiSsid').value || 'EmulatorWiFi',
      netConnected: document.getElementById('mockNetConnected').checked,
      deviceModel: document.getElementById('mockDeviceModel').value || 'Emulator',
      osVersion: document.getElementById('mockOsVersion').value || '14',
      brightness: parseInt(document.getElementById('mockBrightness').value) || 80
    };
  }

  // Load mock data on startup
  loadMockData();

  // Apply mock data button
  document.getElementById('applyMockData').addEventListener('click', async () => {
    const data = getMockData();
    localStorage.setItem('mockData', JSON.stringify(data));

    try {
      const response = await fetch('/api/mock-data', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });

      if (response.ok) {
        addConsoleEntry('success', 'Mock data applied');
      } else {
        addConsoleEntry('error', 'Failed to apply mock data');
      }
    } catch (err) {
      addConsoleEntry('error', 'Error applying mock data: ' + err.message);
    }
  });

  // Reset mock data button
  document.getElementById('resetMockData').addEventListener('click', () => {
    localStorage.removeItem('mockData');
    loadMockData();
    addConsoleEntry('info', 'Mock data reset to defaults');
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

// Setup mobile navigation
document.addEventListener('DOMContentLoaded', () => {
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
// AI Script Inspector
// ============================================================================

let lastInspectorResult = null;
let extractedImprovedScript = null;

function openInspectorModal() {
  document.getElementById('inspectorModal').classList.add('show');
}

function closeInspectorModal() {
  document.getElementById('inspectorModal').classList.remove('show');
}

function resetInspectorUI() {
  document.getElementById('inspectorLoading').style.display = 'none';
  document.getElementById('inspectorResult').innerHTML = `
    <div class="inspector-welcome">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
        <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
      </svg>
      <h3>AI-Powered Script Analysis</h3>
      <p>Click "Analyze Script" to get intelligent feedback on your AIO Launcher widget code.</p>
      <ul>
        <li>API usage validation</li>
        <li>Best practice suggestions</li>
        <li>Error detection with fixes</li>
        <li>Performance improvements</li>
        <li>Improved code generation</li>
      </ul>
    </div>
  `;
  document.getElementById('copyInspectorResult').disabled = true;
  document.getElementById('applyInspectorFix').disabled = true;
  lastInspectorResult = null;
  extractedImprovedScript = null;
}

async function analyzeScript() {
  if (!editor) {
    showToast('Editor not ready', 'error');
    return;
  }

  const script = editor.getValue().trim();
  if (!script) {
    showToast('No script to analyze', 'warning');
    return;
  }

  const settings = getSettings();
  const apiKey = settings.groq?.apiKey;

  if (!apiKey) {
    showToast('Please add your Groq API key in Settings', 'warning');
    closeInspectorModal();
    openSettingsModal();
    return;
  }

  // Show loading
  document.getElementById('inspectorLoading').style.display = 'flex';
  document.getElementById('inspectorResult').innerHTML = '';
  document.getElementById('analyzeScriptBtn').disabled = true;

  try {
    const response = await fetch('/api/inspector/analyze', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ script, apiKey })
    });

    const result = await response.json();

    if (result.error) {
      throw new Error(result.error);
    }

    // Store result and render
    lastInspectorResult = result.analysis;
    renderInspectorResult(result.analysis);

    // Enable buttons
    document.getElementById('copyInspectorResult').disabled = false;

    // Check if there's an improved script to apply
    extractedImprovedScript = extractImprovedScript(result.analysis);
    if (extractedImprovedScript) {
      document.getElementById('applyInspectorFix').disabled = false;
    }

    addConsoleEntry('success', 'Script analysis complete');

  } catch (error) {
    console.error('Inspector error:', error);
    document.getElementById('inspectorResult').innerHTML = `
      <div class="inspector-error">
        <strong>Analysis Failed</strong>
        <p>${escapeHtml(error.message)}</p>
        <p>Make sure your Groq API key is valid and you have API credits.</p>
      </div>
    `;
    addConsoleEntry('error', `Inspector: ${error.message}`);
  } finally {
    document.getElementById('inspectorLoading').style.display = 'none';
    document.getElementById('analyzeScriptBtn').disabled = false;
  }
}

function renderInspectorResult(markdown) {
  // Simple markdown to HTML conversion
  let html = markdown
    // Headers
    .replace(/^### (.+)$/gm, '<h3>$1</h3>')
    .replace(/^## (.+)$/gm, '<h2>$1</h2>')
    .replace(/^# (.+)$/gm, '<h1>$1</h1>')
    // Bold
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    // Italic
    .replace(/\*(.+?)\*/g, '<em>$1</em>')
    // Inline code
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    // Code blocks
    .replace(/```(\w*)\n([\s\S]*?)```/g, (match, lang, code) => {
      return `<pre><code class="language-${lang}">${escapeHtml(code.trim())}</code></pre>`;
    })
    // Lists
    .replace(/^- (.+)$/gm, '<li>$1</li>')
    .replace(/^(\d+)\. (.+)$/gm, '<li>$2</li>')
    // Checkmarks
    .replace(/^- \[x\] (.+)$/gm, '<li class="checked">$1</li>')
    .replace(/^- \[ \] (.+)$/gm, '<li class="unchecked">$1</li>')
    // Line breaks
    .replace(/\n\n/g, '</p><p>')
    .replace(/\n/g, '<br>');

  // Wrap in paragraph
  html = `<p>${html}</p>`;

  // Clean up empty paragraphs and fix list structure
  html = html
    .replace(/<p><\/p>/g, '')
    .replace(/<p>(<h[1-3]>)/g, '$1')
    .replace(/(<\/h[1-3]>)<\/p>/g, '$1')
    .replace(/<p>(<pre>)/g, '$1')
    .replace(/(<\/pre>)<\/p>/g, '$1')
    .replace(/<p>(<li>)/g, '<ul>$1')
    .replace(/(<\/li>)<\/p>/g, '$1</ul>')
    .replace(/<\/li><br><li>/g, '</li><li>');

  document.getElementById('inspectorResult').innerHTML = html;
}

function extractImprovedScript(markdown) {
  // Find Lua code block that appears after "Improved Script" heading
  const improvedMatch = markdown.match(/###\s*Improved Script[\s\S]*?```lua\n([\s\S]*?)```/i);
  if (improvedMatch && improvedMatch[1]) {
    return improvedMatch[1].trim();
  }

  // Fallback: find any lua code block
  const luaMatch = markdown.match(/```lua\n([\s\S]*?)```/);
  if (luaMatch && luaMatch[1] && luaMatch[1].includes('function')) {
    return luaMatch[1].trim();
  }

  return null;
}

function copyInspectorResult() {
  if (!lastInspectorResult) return;

  navigator.clipboard.writeText(lastInspectorResult)
    .then(() => showToast('Result copied to clipboard', 'success'))
    .catch(() => showToast('Failed to copy', 'error'));
}

function applyInspectorFix() {
  if (!extractedImprovedScript || !editor) return;

  if (confirm('Replace current script with the AI-improved version?')) {
    editor.setValue(extractedImprovedScript);
    showToast('Improved script applied', 'success');
    addConsoleEntry('success', 'Applied AI-improved script');
    closeInspectorModal();

    // Auto-run the improved script
    if (autoResumeEnabled) {
      setTimeout(() => executeScript('on_resume'), 500);
    }
  }
}

// Setup inspector events
document.addEventListener('DOMContentLoaded', () => {
  setTimeout(() => {
    // Inspector button
    const inspectBtn = document.getElementById('inspectBtn');
    if (inspectBtn) {
      inspectBtn.addEventListener('click', openInspectorModal);
    }

    // Close inspector
    const closeInspector = document.getElementById('closeInspector');
    if (closeInspector) {
      closeInspector.addEventListener('click', closeInspectorModal);
    }

    // Analyze button
    const analyzeBtn = document.getElementById('analyzeScriptBtn');
    if (analyzeBtn) {
      analyzeBtn.addEventListener('click', analyzeScript);
    }

    // Copy result
    const copyBtn = document.getElementById('copyInspectorResult');
    if (copyBtn) {
      copyBtn.addEventListener('click', copyInspectorResult);
    }

    // Apply fix
    const applyBtn = document.getElementById('applyInspectorFix');
    if (applyBtn) {
      applyBtn.addEventListener('click', applyInspectorFix);
    }

    // Close on overlay click
    const inspectorModal = document.getElementById('inspectorModal');
    if (inspectorModal) {
      inspectorModal.addEventListener('click', (e) => {
        if (e.target.id === 'inspectorModal') {
          closeInspectorModal();
        }
      });
    }
  }, 100);
});

// ============================================================================
// AI Widget Generator
// ============================================================================

let lastGeneratedCode = '';

async function generateWidget() {
  const description = document.getElementById('widgetDescription').value.trim();
  if (!description) {
    showToast('Please enter a widget description', 'error');
    return;
  }

  // Get API key from settings
  const apiKey = document.getElementById('settingGroqKey').value.trim();
  if (!apiKey) {
    showToast('Please set your Groq API key in Settings', 'error');
    document.getElementById('settingsModal').classList.add('active');
    return;
  }

  // Show loading
  document.getElementById('generatorLoading').style.display = 'flex';
  document.getElementById('generatorResult').style.display = 'none';
  document.getElementById('generateWidgetBtn').disabled = true;

  try {
    const response = await fetch('/api/generate-widget', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ description, apiKey })
    });

    const data = await response.json();

    if (data.success && data.code) {
      lastGeneratedCode = data.code;
      document.getElementById('generatedCodePreview').textContent = data.code;
      document.getElementById('generatorResult').style.display = 'block';
      showToast('Widget generated successfully!', 'success');
      addConsoleEntry('success', `Generated widget from description: "${description.substring(0, 50)}..."`);
    } else {
      showToast(data.error || 'Failed to generate widget', 'error');
      addConsoleEntry('error', `Generator error: ${data.error}`);
    }
  } catch (error) {
    showToast('Error connecting to server', 'error');
    addConsoleEntry('error', `Generator connection error: ${error.message}`);
  } finally {
    document.getElementById('generatorLoading').style.display = 'none';
    document.getElementById('generateWidgetBtn').disabled = false;
  }
}

function copyGeneratedCode() {
  if (!lastGeneratedCode) return;
  navigator.clipboard.writeText(lastGeneratedCode)
    .then(() => showToast('Code copied to clipboard', 'success'))
    .catch(() => showToast('Failed to copy', 'error'));
}

function loadGeneratedCode() {
  if (!lastGeneratedCode || !editor) return;
  editor.setValue(lastGeneratedCode);
  showToast('Widget loaded in editor', 'success');
  addConsoleEntry('info', 'Loaded AI-generated widget in editor');

  // Switch to editor tab if on mobile or collapsed
  const editorPanel = document.getElementById('editorPanel');
  if (editorPanel && editorPanel.classList.contains('collapsed')) {
    editorPanel.classList.remove('collapsed');
  }

  // Auto-run if enabled
  if (autoResumeEnabled) {
    setTimeout(() => executeScript('on_resume'), 500);
  }
}

// Setup generator events
document.addEventListener('DOMContentLoaded', () => {
  setTimeout(() => {
    // Generate button
    const generateBtn = document.getElementById('generateWidgetBtn');
    if (generateBtn) {
      generateBtn.addEventListener('click', generateWidget);
    }

    // Copy generated code
    const copyGenBtn = document.getElementById('copyGeneratedCode');
    if (copyGenBtn) {
      copyGenBtn.addEventListener('click', copyGeneratedCode);
    }

    // Load generated code in editor
    const loadGenBtn = document.getElementById('loadGeneratedCode');
    if (loadGenBtn) {
      loadGenBtn.addEventListener('click', loadGeneratedCode);
    }

    // Example buttons
    document.querySelectorAll('.example-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const example = btn.dataset.example;
        if (example) {
          document.getElementById('widgetDescription').value = example;
        }
      });
    });
  }, 100);
});

// ============================================================================
// TEMPLATES & SNIPPETS SYSTEM
// ============================================================================

const WIDGET_TEMPLATES = {
  'basic': `-- Basic Widget Template
-- A simple widget with standard callbacks

local WIDGET_NAME = "My Widget"

-- State
local data = {}

-- Helper functions
local function render()
  local lines = {
    "📦 " .. WIDGET_NAME,
    "",
    "Hello from your widget!",
    "",
    "━━━━━━━━━━━━━━━━━━━━",
    "Tap to interact"
  }
  ui:show_text(table.concat(lines, "\\n"))
end

-- Callbacks
function on_resume()
  render()
end

function on_click()
  system:toast("Widget clicked!")
  render()
end

function on_long_click()
  ui:show_context_menu({
    "Option 1",
    "Option 2",
    "Option 3"
  })
end

function on_context_menu_click(index)
  system:toast("Selected option " .. index)
end
`,

  'http-api': `-- HTTP API Widget Template
-- Fetch and display data from REST APIs

local API_URL = "https://api.example.com/data"
local REFRESH_MINUTES = 5

-- State
local state = {
  loading = false,
  error = nil,
  data = nil,
  last_refresh = 0
}

-- Helper functions
local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end

local function render()
  if state.loading then
    ui:show_text("⏳ Loading...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\\n\\nTap to retry")
    return
  end

  local lines = {
    "🌐 API Widget",
    "",
    "Data: " .. tostring(state.data),
    "",
    "━━━━━━━━━━━━━━━━━━━━",
    "Last updated: " .. os.date("%H:%M")
  }
  ui:show_text(table.concat(lines, "\\n"))
end

local function fetch_data()
  state.loading = true
  state.error = nil
  render()

  http:get(API_URL, function(body, code)
    state.loading = false

    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        state.data = data
        state.last_refresh = os.time()
      else
        state.error = "Failed to parse response"
      end
    else
      state.error = "Request failed (code: " .. tostring(code) .. ")"
    end

    render()
  end)
end

-- Callbacks
function on_resume()
  local elapsed = os.time() - state.last_refresh
  if elapsed > REFRESH_MINUTES * 60 or not state.data then
    fetch_data()
  else
    render()
  end
end

function on_click()
  if state.error then
    fetch_data()
  else
    system:toast("Data refreshed!")
    fetch_data()
  end
end

function on_long_click()
  ui:show_context_menu({
    "🔄 Refresh",
    "⚙️ Settings"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    fetch_data()
  elseif index == 2 then
    ui:show_text("⚙️ Settings\\n\\nAPI URL: " .. API_URL)
  end
end
`,

  'chart': `-- Chart Widget Template
-- Display data with visual charts

local STORAGE_KEY = "chart_data"
local MAX_POINTS = 20

-- State
local values = {}

-- Helper functions
local function load_data()
  local data = storage:get(STORAGE_KEY)
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return {}
end

local function save_data()
  storage:put(STORAGE_KEY, json.encode(values))
end

local function get_average()
  if #values == 0 then return 0 end
  local sum = 0
  for _, v in ipairs(values) do
    sum = sum + v
  end
  return sum / #values
end

local function render()
  local avg = get_average()
  local latest = values[#values] or 0

  local lines = {
    "📊 Chart Widget",
    "",
    "📈 Latest: " .. latest,
    "📉 Average: " .. string.format("%.1f", avg),
    "📋 Points: " .. #values,
    "",
    "━━━━━━━━━━━━━━━━━━━━",
    "Tap to add random value"
  }
  ui:show_text(table.concat(lines, "\\n"))

  -- Show chart if we have data
  if #values >= 2 then
    ui:show_chart(values, nil, "Data Points", true)
  end
end

local function add_value(val)
  table.insert(values, val)
  while #values > MAX_POINTS do
    table.remove(values, 1)
  end
  save_data()
  render()
end

-- Callbacks
function on_resume()
  values = load_data()
  render()
end

function on_click()
  local new_val = math.random(1, 100)
  add_value(new_val)
  system:toast("Added: " .. new_val)
end

function on_long_click()
  ui:show_context_menu({
    "➕ Add Value",
    "🗑️ Clear Data",
    "📊 Show Stats"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    add_value(math.random(1, 100))
  elseif index == 2 then
    values = {}
    save_data()
    system:toast("Data cleared")
    render()
  elseif index == 3 then
    local stats = "📊 Statistics\\n\\n"
    stats = stats .. "Points: " .. #values .. "\\n"
    stats = stats .. "Average: " .. string.format("%.1f", get_average()) .. "\\n"
    if #values > 0 then
      stats = stats .. "Min: " .. math.min(table.unpack(values)) .. "\\n"
      stats = stats .. "Max: " .. math.max(table.unpack(values))
    end
    ui:show_text(stats)
  end
end
`,

  'storage': `-- Storage Widget Template
-- Persistent data with JSON storage

local STORAGE_KEY = "my_widget_data"

-- State
local state = {
  items = {},
  count = 0
}

-- Helper functions
local function load_data()
  local data = storage:get(STORAGE_KEY)
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return { items = {}, count = 0 }
end

local function save_data()
  storage:put(STORAGE_KEY, json.encode(state))
end

local function render()
  local lines = {
    "💾 Storage Widget",
    "",
    "📦 Items: " .. #state.items,
    "🔢 Counter: " .. state.count,
    ""
  }

  if #state.items > 0 then
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")
    for i, item in ipairs(state.items) do
      table.insert(lines, i .. ". " .. item)
    end
  end

  table.insert(lines, "")
  table.insert(lines, "Tap: +1 | Long: Menu")

  ui:show_text(table.concat(lines, "\\n"))
end

-- Callbacks
function on_resume()
  state = load_data()
  render()
end

function on_click()
  state.count = state.count + 1
  save_data()
  system:toast("Count: " .. state.count)
  render()
end

function on_long_click()
  ui:show_context_menu({
    "➕ Add Item",
    "➖ Remove Last",
    "🔄 Reset Counter",
    "🗑️ Clear All"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    table.insert(state.items, "Item " .. (#state.items + 1))
    save_data()
    system:toast("Item added")
  elseif index == 2 then
    if #state.items > 0 then
      table.remove(state.items)
      save_data()
      system:toast("Item removed")
    end
  elseif index == 3 then
    state.count = 0
    save_data()
    system:toast("Counter reset")
  elseif index == 4 then
    state = { items = {}, count = 0 }
    save_data()
    system:toast("All data cleared")
  end
  render()
end
`,

  'mikrotik': `-- MikroTik Widget Template
-- Router monitoring via REST API

local CONFIG = {
  ip = "10.1.1.1",
  user = "admin",
  pass = "admin123"
}

-- State
local state = {
  loading = true,
  error = nil,
  cpu = 0,
  ram = 0,
  uptime = ""
}

-- Helper functions
local function get_url(endpoint)
  return string.format("http://%s:%s@%s%s",
    CONFIG.user, CONFIG.pass, CONFIG.ip, endpoint)
end

local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end

local function progress_bar(value, max, width)
  width = width or 10
  if max == 0 then max = 1 end
  local pct = math.min(value / max, 1)
  local filled = math.floor(pct * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

local function render()
  if state.loading then
    ui:show_text("⏳ Connecting to " .. CONFIG.ip .. "...")
    return
  end

  if state.error then
    ui:show_text("❌ " .. state.error .. "\\n\\nTap to retry")
    return
  end

  local lines = {
    "🔧 MikroTik Monitor",
    "",
    string.format("🖥 CPU  %s %d%%", progress_bar(state.cpu, 100, 8), state.cpu),
    string.format("💾 RAM  %s %d%%", progress_bar(state.ram, 100, 8), state.ram),
    "⏱ Uptime: " .. state.uptime,
    "",
    "━━━━━━━━━━━━━━━━━━━━",
    "Tap to refresh"
  }
  ui:show_text(table.concat(lines, "\\n"))
end

local function fetch_data()
  state.loading = true
  state.error = nil
  render()

  http:get(get_url("/rest/system/resource"), function(body, code)
    state.loading = false

    if code == 200 and body then
      local data = safe_decode(body)
      if data then
        local total_mem = tonumber(data["total-memory"]) or 1
        local free_mem = tonumber(data["free-memory"]) or 0
        state.cpu = tonumber(data["cpu-load"]) or 0
        state.ram = math.floor(((total_mem - free_mem) / total_mem) * 100)
        state.uptime = data["uptime"] or "?"
      else
        state.error = "Failed to parse response"
      end
    else
      state.error = "Connection failed"
    end

    render()
  end)
end

-- Callbacks
function on_resume()
  fetch_data()
end

function on_click()
  fetch_data()
end

function on_long_click()
  ui:show_context_menu({
    "🔄 Refresh",
    "🌐 Open WebFig",
    "⚙️ Settings"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    fetch_data()
  elseif index == 2 then
    system:open_browser("http://" .. CONFIG.ip)
  elseif index == 3 then
    ui:show_text("⚙️ Settings\\n\\nRouter: " .. CONFIG.ip)
  end
end
`,

  'tracker': `-- Tracker Widget Template
-- Track habits, goals, or metrics over time

local STORAGE_KEY = "tracker_data"
local MAX_HISTORY = 30

-- State
local state = {
  today_value = 0,
  goal = 10,
  history = {},
  current_date = ""
}

-- Helper functions
local function get_today()
  return os.date("%Y-%m-%d")
end

local function load_data()
  local data = storage:get(STORAGE_KEY)
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return { today = 0, goal = 10, history = {}, date = "" }
end

local function save_data()
  storage:put(STORAGE_KEY, json.encode({
    today = state.today_value,
    goal = state.goal,
    history = state.history,
    date = state.current_date
  }))
end

local function reset_if_new_day(saved)
  local today = get_today()
  if saved.date ~= today then
    if saved.date ~= "" then
      table.insert(state.history, { date = saved.date, value = saved.today })
      while #state.history > MAX_HISTORY do
        table.remove(state.history, 1)
      end
    end
    state.today_value = 0
    state.current_date = today
  else
    state.today_value = saved.today or 0
    state.current_date = today
  end
end

local function get_streak()
  local streak = 0
  if state.today_value >= state.goal then
    streak = 1
  end
  for i = #state.history, 1, -1 do
    if state.history[i].value >= state.goal then
      streak = streak + 1
    else
      break
    end
  end
  return streak
end

local function progress_bar(value, max)
  local pct = math.min(value / max, 1)
  local filled = math.floor(pct * 10)
  return string.rep("█", filled) .. string.rep("░", 10 - filled)
end

local function render()
  local percent = math.floor((state.today_value / state.goal) * 100)
  local streak = get_streak()

  local lines = {
    "📈 Daily Tracker",
    "",
    "📊 Today: " .. state.today_value .. "/" .. state.goal,
    "   " .. progress_bar(state.today_value, state.goal) .. " " .. percent .. "%",
    ""
  }

  if streak > 0 then
    table.insert(lines, "🔥 Streak: " .. streak .. " days")
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")
  table.insert(lines, "Tap: +1 | Long: Menu")

  ui:show_text(table.concat(lines, "\\n"))

  -- Show chart
  local values = {}
  for _, h in ipairs(state.history) do
    table.insert(values, h.value)
  end
  table.insert(values, state.today_value)
  if #values >= 2 then
    ui:show_chart(values, nil, "Progress", true)
  end
end

-- Callbacks
function on_resume()
  local saved = load_data()
  state.goal = saved.goal or 10
  state.history = saved.history or {}
  reset_if_new_day(saved)
  render()
end

function on_click()
  state.today_value = state.today_value + 1
  save_data()
  if state.today_value == state.goal then
    system:toast("🎉 Goal reached!")
  else
    system:toast("+" .. 1)
  end
  render()
end

function on_long_click()
  ui:show_context_menu({
    "➕ Add 1",
    "➕ Add 5",
    "➖ Remove 1",
    "🔄 Reset Today",
    "📊 Statistics"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    state.today_value = state.today_value + 1
  elseif index == 2 then
    state.today_value = state.today_value + 5
  elseif index == 3 then
    state.today_value = math.max(0, state.today_value - 1)
  elseif index == 4 then
    state.today_value = 0
  elseif index == 5 then
    local total = state.today_value
    for _, h in ipairs(state.history) do
      total = total + h.value
    end
    local days = #state.history + 1
    local avg = days > 0 and total / days or 0
    ui:show_text("📊 Statistics\\n\\nTotal: " .. total .. "\\nDays: " .. days .. "\\nAvg: " .. string.format("%.1f", avg))
    return
  end
  save_data()
  render()
end
`
};

const CODE_SNIPPETS = {
  'http-get': `http:get("https://api.example.com/data", function(body, code)
  if code == 200 and body then
    local data = json.decode(body)
    -- Process data
  else
    -- Handle error
  end
end)`,

  'http-post': `local headers = {
  "Content-Type: application/json",
  "Authorization: Bearer YOUR_TOKEN"
}

local body = json.encode({
  key = "value"
})

http:post("https://api.example.com/data", body, headers, function(response, code)
  if code == 200 then
    -- Success
  else
    -- Handle error
  end
end)`,

  'storage-get': `local function load_data()
  local data = storage:get("my_key")
  if data then
    local decoded = json.decode(data)
    if decoded then
      return decoded
    end
  end
  return { default = "value" }
end`,

  'storage-put': `local function save_data(data)
  storage:put("my_key", json.encode(data))
end

-- Usage:
save_data({ count = 42, items = {"a", "b", "c"} })`,

  'show-text': `local lines = {
  "📦 Widget Title",
  "",
  "Line 1 content",
  "Line 2 content",
  "",
  "━━━━━━━━━━━━━━━━━━━━",
  "Footer text"
}
ui:show_text(table.concat(lines, "\\n"))`,

  'show-chart': `-- Values for the chart (array of numbers)
local values = { 10, 25, 15, 30, 20, 35 }

-- Optional: labels for each point
local labels = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

-- Show the chart
ui:show_chart(values, labels, "My Chart Title", true)`,

  'context-menu': `function on_long_click()
  ui:show_context_menu({
    "🔄 Option 1",
    "⚙️ Option 2",
    "━━━━━━━━━━━━",
    "🗑️ Delete"
  })
end

function on_context_menu_click(index)
  if index == 1 then
    -- Handle option 1
  elseif index == 2 then
    -- Handle option 2
  elseif index == 4 then
    -- Handle delete
  end
end`,

  'progress-bar': `-- Simple progress bar function
local function progress_bar(value, max, width)
  width = width or 10
  if max == 0 then max = 1 end
  local pct = math.min(value / max, 1)
  local filled = math.floor(pct * width)
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

-- Usage
ui:show_progress_bar("Loading", 75, 100, "#4CAF50")

-- Or build your own
local bar = progress_bar(75, 100, 10)
ui:show_text("Progress: " .. bar .. " 75%")`,

  'json-parse': `local function safe_decode(data)
  if not data or data == "" then return nil end
  local ok, result = pcall(json.decode, data)
  if ok then return result end
  return nil
end

-- Usage
local data = safe_decode(json_string)
if data then
  -- Access data.field
end`,

  'format-bytes': `local function format_bytes(bytes)
  bytes = tonumber(bytes) or 0
  if bytes >= 1073741824 then
    return string.format("%.1f GB", bytes / 1073741824)
  elseif bytes >= 1048576 then
    return string.format("%.1f MB", bytes / 1048576)
  elseif bytes >= 1024 then
    return string.format("%.1f KB", bytes / 1024)
  else
    return string.format("%d B", bytes)
  end
end

-- Usage
local size = format_bytes(1536000)  -- "1.5 MB"`
};

function loadTemplate(templateName) {
  const template = WIDGET_TEMPLATES[templateName];
  if (template && editor) {
    editor.setValue(template);
    showTemplateToast('Template loaded: ' + templateName);

    // Switch to editor panel if on mobile
    const editorPanel = document.getElementById('editorPanel');
    if (editorPanel) {
      editorPanel.scrollIntoView({ behavior: 'smooth' });
    }
  }
}

function insertSnippet(snippetName) {
  const snippet = CODE_SNIPPETS[snippetName];
  if (snippet && editor) {
    const position = editor.getPosition();
    const selection = editor.getSelection();

    editor.executeEdits('', [{
      range: selection,
      text: snippet,
      forceMoveMarkers: true
    }]);

    showTemplateToast('Snippet inserted: ' + snippetName);
    editor.focus();
  }
}

function showTemplateToast(message) {
  const existing = document.querySelector('.template-toast');
  if (existing) existing.remove();

  const toast = document.createElement('div');
  toast.className = 'template-toast';
  toast.textContent = message;
  document.body.appendChild(toast);

  setTimeout(() => toast.remove(), 2000);
}

function exportWidget() {
  if (!editor) return;

  const code = editor.getValue();
  if (!code.trim()) {
    showTemplateToast('No code to export');
    return;
  }

  // Get widget name from first comment or generate one
  const nameMatch = code.match(/^--\s*(.+)/);
  const widgetName = nameMatch ? nameMatch[1].replace(/[^a-zA-Z0-9]/g, '_').toLowerCase() : 'widget';
  const filename = widgetName + '.lua';

  const blob = new Blob([code], { type: 'text/plain' });
  const url = URL.createObjectURL(blob);

  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();

  URL.revokeObjectURL(url);
  showTemplateToast('Widget exported: ' + filename);
}

function importWidget() {
  document.getElementById('importFileInput').click();
}

function handleImportFile(event) {
  const file = event.target.files[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = function(e) {
    if (editor) {
      editor.setValue(e.target.result);
      showTemplateToast('Widget imported: ' + file.name);
    }
  };
  reader.readAsText(file);

  // Reset input so same file can be imported again
  event.target.value = '';
}

async function importFromUrl() {
  const url = prompt('Enter widget URL (.lua file):');
  if (!url) return;

  try {
    const response = await fetch(url);
    if (!response.ok) throw new Error('Failed to fetch');

    const code = await response.text();
    if (editor) {
      editor.setValue(code);
      showTemplateToast('Widget imported from URL');
    }
  } catch (error) {
    showTemplateToast('Failed to import: ' + error.message);
  }
}

// Setup templates event listeners
document.addEventListener('DOMContentLoaded', function() {
  setTimeout(() => {
    // Template cards
    document.querySelectorAll('.template-card').forEach(card => {
      card.addEventListener('click', () => {
        const template = card.dataset.template;
        if (template) {
          loadTemplate(template);
        }
      });
    });

    // Snippet cards
    document.querySelectorAll('.snippet-card').forEach(card => {
      card.addEventListener('click', () => {
        const snippet = card.dataset.snippet;
        if (snippet) {
          insertSnippet(snippet);
        }
      });
    });

    // Export/Import buttons
    const exportBtn = document.getElementById('exportWidgetBtn');
    if (exportBtn) exportBtn.addEventListener('click', exportWidget);

    const importBtn = document.getElementById('importWidgetBtn');
    if (importBtn) importBtn.addEventListener('click', importWidget);

    const importUrlBtn = document.getElementById('importFromUrlBtn');
    if (importUrlBtn) importUrlBtn.addEventListener('click', importFromUrl);

    const importFileInput = document.getElementById('importFileInput');
    if (importFileInput) importFileInput.addEventListener('change', handleImportFile);
  }, 100);
});

// ============================================================================
// Initialization Complete
// ============================================================================

console.log('AIO Widget Emulator initialized');
console.log('Shortcuts: Ctrl+Enter = Run, Ctrl+S = Save');

// ============================================================================
// Device Deployment
// ============================================================================

// State for device management
let connectedDevices = [];
let selectedDeviceId = null;

// Fetch connected devices from server
async function fetchDevices() {
  try {
    const response = await fetch('/api/devices');
    const data = await response.json();
    
    if (data.success) {
      connectedDevices = data.devices || [];
      updateDeviceSelect();
    } else {
      console.warn('Failed to fetch devices:', data.error);
      connectedDevices = [];
      updateDeviceSelect();
    }
  } catch (error) {
    console.error('Error fetching devices:', error);
    connectedDevices = [];
    updateDeviceSelect();
  }
}

// Update device dropdown
function updateDeviceSelect() {
  const select = document.getElementById('deviceSelect');
  if (!select) return;
  
  select.innerHTML = connectedDevices.length === 0
    ? '<option value="">No Devices</option>'
    : '<option value="">Select Device...</option>';
  
  for (const device of connectedDevices) {
    const option = document.createElement('option');
    option.value = device.id;
    option.textContent = device.label;
    select.appendChild(option);
  }
  
  // Restore previous selection if still available
  if (selectedDeviceId) {
    const exists = connectedDevices.some(d => d.id === selectedDeviceId);
    if (exists) {
      select.value = selectedDeviceId;
    } else {
      selectedDeviceId = null;
    }
  }
}

// Deploy widget to selected device
async function deployToDevice() {
  const deviceSelect = document.getElementById('deviceSelect');
  const deployBtn = document.getElementById('deployBtn');
  
  selectedDeviceId = deviceSelect?.value;
  
  if (!selectedDeviceId) {
    showToast('Please select a device first', 'warning');
    return;
  }
  
  if (!window.editor) {
    showToast('No editor available', 'error');
    return;
  }
  
  const widgetCode = window.editor.getValue();
  if (!widgetCode.trim()) {
    showToast('No widget code to deploy', 'warning');
    return;
  }
  
  // Get widget name from metadata or use default
  const nameMatch = widgetCode.match(/--\s*name\s*=\s*["']([^"']+)["']/);
  const widgetName = nameMatch ? nameMatch[1].replace(/\s+/g, '_').toLowerCase() : 'widget';
  
  // Disable button during deploy
  if (deployBtn) {
    deployBtn.disabled = true;
    deployBtn.innerHTML = '<span>Deploying...</span>';
  }
  
  try {
    const response = await fetch('/api/deploy-widget', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        widgetCode,
        widgetName,
        deviceId: selectedDeviceId
      })
    });
    
    const data = await response.json();
    
    if (data.success) {
      showToast(`Deployed ${data.widgetName} to device`, 'success');
    } else {
      showToast(`Deploy failed: ${data.error}`, 'error');
    }
  } catch (error) {
    showToast(`Deploy error: ${error.message}`, 'error');
  } finally {
    if (deployBtn) {
      deployBtn.disabled = false;
      deployBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/></svg><span>Deploy</span>';
    }
  }
}

// Simple toast notification (uses existing or creates new)
function showToast(message, type = 'info') {
  // Check if there's an existing toast function or element
  let toast = document.getElementById('toast');
  
  if (!toast) {
    toast = document.createElement('div');
    toast.id = 'toast';
    toast.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);padding:12px 24px;border-radius:8px;color:white;font-size:14px;z-index:9999;opacity:0;transition:opacity 0.3s';
    document.body.appendChild(toast);
  }
  
  const colors = {
    success: '#10b981',
    error: '#ef4444',
    warning: '#f59e0b',
    info: '#3b82f6'
  };
  
  toast.style.backgroundColor = colors[type] || colors.info;
  toast.textContent = message;
  toast.style.opacity = '1';
  
  setTimeout(() => {
    toast.style.opacity = '0';
  }, 3000);
}

// Initialize device deployment on page load
document.addEventListener('DOMContentLoaded', () => {
  const deployBtn = document.getElementById('deployBtn');
  const refreshDevicesBtn = document.getElementById('refreshDevicesBtn');
  const deviceSelect = document.getElementById('deviceSelect');
  
  if (deployBtn) {
    deployBtn.addEventListener('click', deployToDevice);
  }
  
  if (refreshDevicesBtn) {
    refreshDevicesBtn.addEventListener('click', () => {
      showToast('Scanning for devices...', 'info');
      fetchDevices();
    });
  }
  
  if (deviceSelect) {
    deviceSelect.addEventListener('change', (e) => {
      selectedDeviceId = e.target.value;
    });
  }
  
  // Auto-fetch devices on load
  setTimeout(fetchDevices, 1000);
});

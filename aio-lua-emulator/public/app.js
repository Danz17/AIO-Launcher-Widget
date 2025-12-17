// Monaco Editor instance
let editor;
let autoResumeEnabled = true;
let autoResumeTimeout;

// Initialize Monaco Editor
require.config({ paths: { vs: 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs' } });

require(['vs/editor/editor.main'], function() {
    editor = monaco.editor.create(document.getElementById('editor'), {
        value: `-- name = "My Widget"
-- description = "Widget description"
-- foldable = "true"

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
end`,
        language: 'lua',
        theme: 'vs-dark',
        automaticLayout: true,
        minimap: { enabled: false },
        fontSize: 14,
        lineNumbers: 'on',
        roundedSelection: false,
        scrollBeyondLastLine: false,
        readOnly: false,
        cursorStyle: 'line',
        folding: true,
        fontFamily: "'Roboto Mono', 'Consolas', 'Monaco', monospace"
    });

    // Listen for content changes
    editor.onDidChangeModelContent(() => {
        if (autoResumeEnabled) {
            clearTimeout(autoResumeTimeout);
            autoResumeTimeout = setTimeout(() => {
                executeScript('on_resume');
            }, 1000); // Auto-resume 1 second after typing stops
        }
    });

    // Initial execution
    executeScript('on_resume');
});

// Load available widgets
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
            option.dataset.category = widget.category;
            select.appendChild(option);
        });
    } catch (error) {
        console.error('Failed to load widgets:', error);
        addLogEntry('error', 'Failed to load widget list');
    }
}

// Load widget content
async function loadWidget(path) {
    try {
        const response = await fetch(`/api/widgets/load?path=${encodeURIComponent(path)}`);
        const data = await response.json();
        
        if (data.content && editor) {
            editor.setValue(data.content);
            addLogEntry('success', `Loaded widget: ${path.split(/[/\\]/).pop()}`);
        }
    } catch (error) {
        console.error('Failed to load widget:', error);
        addLogEntry('error', 'Failed to load widget');
    }
}

// Load available mocks
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

// Execute Lua script
async function executeScript(functionName = 'on_resume') {
    try {
        const script = editor.getValue();
        const mockFile = document.getElementById('mockSelect').value;
        
        let mockData = null;
        if (mockFile) {
            const mockResponse = await fetch(`/api/mocks/${mockFile}`);
            mockData = await mockResponse.json();
        }
        
        addLogEntry('info', `Executing ${functionName}()...`);
        
        const response = await fetch('/api/execute', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ script, functionName, mockData })
        });
        
        const result = await response.json();
        
        if (result.success) {
            displayOutput(result.output);
            if (!result.functionExists) {
                addLogEntry('warning', `Function ${functionName}() not found in script`);
            } else {
                addLogEntry('success', `Executed ${functionName}() successfully`);
            }
        } else {
            displayError(result.error);
            addLogEntry('error', `Execution failed: ${result.error}`);
        }
    } catch (error) {
        console.error('Execution error:', error);
        displayError(error.message);
        addLogEntry('error', `Request failed: ${error.message}`);
    }
}

// Display output in widget
function displayOutput(output) {
    const widgetOutput = document.getElementById('widgetOutput');
    
    // Handle non-string output
    if (!output) {
        widgetOutput.innerHTML = '<div class="widget-placeholder"><span class="placeholder-icon">⚠️</span><p>No output from widget</p></div>';
        return;
    }
    
    // Convert to string if needed
    const outputStr = typeof output === 'string' ? output : String(output);
    
    if (outputStr.trim() === '') {
        widgetOutput.innerHTML = '<div class="widget-placeholder"><span class="placeholder-icon">⚠️</span><p>No output from widget</p></div>';
        return;
    }
    
    // Format the output with proper line breaks and spacing
    const formattedOutput = outputStr
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/\n/g, '<br>');
    
    widgetOutput.innerHTML = formattedOutput;
}

// Display error
function displayError(error) {
    const widgetOutput = document.getElementById('widgetOutput');
    widgetOutput.innerHTML = `
        <div style="color: #f44336; padding: 1rem;">
            <div style="font-size: 1.2rem; margin-bottom: 0.5rem;">❌ Error</div>
            <div style="font-size: 0.9rem; opacity: 0.9;">${error.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</div>
        </div>
    `;
}

// Add log entry (enhanced with collapsible details)
function addLogEntry(type, message, details = null) {
    const httpLog = document.getElementById('httpLog');
    const entry = document.createElement('div');
    entry.className = `log-entry ${type}`;
    
    const time = new Date().toLocaleTimeString();
    
    // Create header with fold icon
    const header = document.createElement('div');
    header.className = 'log-entry-header';
    header.innerHTML = `
        <span class="log-fold-icon">▼</span>
        <div class="log-time">${time}</div>
        <div class="log-status">${message}</div>
    `;
    entry.appendChild(header);
    
    // Add details if provided
    if (details) {
        const detailsDiv = document.createElement('div');
        detailsDiv.className = 'log-details';
        detailsDiv.innerHTML = details;
        entry.appendChild(detailsDiv);
    }
    
    // Auto-collapse by default
    entry.classList.add('collapsed');
    
    // Toggle collapse on click
    header.addEventListener('click', () => {
        entry.classList.toggle('collapsed');
    });
    
    httpLog.insertBefore(entry, httpLog.firstChild);
    
    // Limit log entries
    while (httpLog.children.length > 50) {
        httpLog.removeChild(httpLog.lastChild);
    }
}

// Update clock in status bar
function updateClock() {
    const time = new Date();
    const hours = time.getHours().toString().padStart(2, '0');
    const minutes = time.getMinutes().toString().padStart(2, '0');
    document.getElementById('statusTime').textContent = `${hours}:${minutes}`;
}

// HTTP Mode Toggle
async function updateHttpMode(isReal) {
    try {
        const mode = isReal ? 'real' : 'mock';
        await fetch('/api/http-mode', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ mode })
        });
        
        document.getElementById('httpModeLabel').textContent = mode === 'real' ? 'Real' : 'Mock';
        addLogEntry('info', `HTTP mode: ${mode}`);
    } catch (error) {
        console.error('Failed to update HTTP mode:', error);
    }
}

// Event Listeners
document.addEventListener('DOMContentLoaded', () => {
    // Update clock every second
    updateClock();
    setInterval(updateClock, 1000);
    
    // Load widgets and mocks
    loadWidgets();
    loadMocks();
    
    // Widget selector
    document.getElementById('widgetSelect').addEventListener('change', (e) => {
        if (e.target.value) {
            loadWidget(e.target.value);
        }
    });
    
    // HTTP mode toggle
    document.getElementById('httpModeToggle').addEventListener('change', (e) => {
        updateHttpMode(e.target.checked);
    });
    
    // Auto resume toggle
    document.getElementById('autoResumeToggle').addEventListener('change', (e) => {
        autoResumeEnabled = e.target.checked;
        addLogEntry('info', `Auto-resume: ${autoResumeEnabled ? 'enabled' : 'disabled'}`);
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
        addLogEntry('success', 'Script saved');
    });
    
    // Clear log button
    document.getElementById('clearLogBtn').addEventListener('click', () => {
        document.getElementById('httpLog').innerHTML = '';
    });
    
    // Fold/Unfold all logs button
    let allFolded = true;
    document.getElementById('foldAllBtn').addEventListener('click', (e) => {
        const httpLog = document.getElementById('httpLog');
        const entries = httpLog.querySelectorAll('.log-entry');
        const btn = e.target;
        
        entries.forEach(entry => {
            if (allFolded) {
                entry.classList.remove('collapsed');
            } else {
                entry.classList.add('collapsed');
            }
        });
        
        allFolded = !allFolded;
        btn.textContent = allFolded ? '📋 Fold' : '📖 Unfold';
    });
    
    // Mock selector
    document.getElementById('mockSelect').addEventListener('change', () => {
        if (autoResumeEnabled) {
            executeScript('on_resume');
        }
    });
    
    // Edit mock button
    document.getElementById('editMockBtn').addEventListener('click', () => {
        const mockFile = document.getElementById('mockSelect').value;
        if (mockFile) {
            alert(`Mock editing UI coming soon!\nEdit ${mockFile} manually in the mocks/ directory for now.`);
        }
    });
});

// Global keyboard shortcuts
document.addEventListener('keydown', (e) => {
    // Ctrl/Cmd + Enter to execute
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault();
        executeScript('on_resume');
    }
    
    // Ctrl/Cmd + S to save
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        document.getElementById('saveBtn').click();
    }
});

console.log('🚀 AIO Launcher Widget Emulator initialized');
console.log('📝 Tip: Press Ctrl/Cmd + Enter to execute, Ctrl/Cmd + S to save');

// UI API Emulation for AIO Launcher
import chalk from 'chalk';

let outputBuffer = [];
let contextMenuItems = [];
let contextMenuCallback = null;
let widgetTitle = 'Widget';

export const ui = {
    show_text: function(text) {
        // Replace buffer instead of appending (mimics AIO Launcher behavior)
        outputBuffer = [text];
        console.log(chalk.cyan('\n━━━━━━━━━━━━━━━━━━━━━━━━━'));
        console.log(chalk.bold.cyan('Widget Output:'));
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━'));
        console.log(text);
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
    },

    show_lines: function(lines, senders) {
        // Display a list of lines with optional senders (for message-style display)
        outputBuffer = [];
        console.log(chalk.cyan('\n━━━━━━━━━━━━━━━━━━━━━━━━━'));
        console.log(chalk.bold.cyan('Widget Lines:'));
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━'));

        if (Array.isArray(lines)) {
            lines.forEach((line, idx) => {
                const sender = senders && senders[idx] ? chalk.bold(senders[idx] + ': ') : '';
                const output = sender + line;
                outputBuffer.push(output);
                console.log(output);
            });
        }
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
    },

    show_buttons: function(names, colors) {
        // Display a row of buttons with optional colors
        outputBuffer = [];
        console.log(chalk.cyan('\n━━━━━━━━━━━━━━━━━━━━━━━━━'));
        console.log(chalk.bold.cyan('Widget Buttons:'));
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━'));

        if (Array.isArray(names)) {
            const buttons = names.map((name, idx) => {
                const color = colors && colors[idx] ? colors[idx] : 'default';
                return `[ ${name} ]`;
            });
            const output = buttons.join('  ');
            outputBuffer.push(output);
            console.log(chalk.blue(output));
        }
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
    },

    show_table: function(data, mainColumn, centering) {
        // Display a formatted table
        outputBuffer = [];
        console.log(chalk.cyan('\n━━━━━━━━━━━━━━━━━━━━━━━━━'));
        console.log(chalk.bold.cyan('Widget Table:'));
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━'));

        if (Array.isArray(data)) {
            data.forEach(row => {
                if (Array.isArray(row)) {
                    const line = row.join(' │ ');
                    outputBuffer.push(line);
                    console.log(line);
                } else {
                    outputBuffer.push(String(row));
                    console.log(String(row));
                }
            });
        }
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
    },

    show_progress_bar: function(text, current, max, color) {
        // Display a progress bar
        const percent = Math.min(100, Math.max(0, (current / max) * 100));
        const barWidth = 20;
        const filled = Math.floor((percent / 100) * barWidth);
        const bar = '█'.repeat(filled) + '░'.repeat(barWidth - filled);

        const output = `${text}\n[${bar}] ${percent.toFixed(1)}%`;
        outputBuffer = [output];

        console.log(chalk.cyan('\n━━━━━━━━━━━━━━━━━━━━━━━━━'));
        console.log(chalk.bold.cyan('Widget Progress:'));
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━'));
        console.log(output);
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
    },

    show_chart: function(points, format, title, showGrid, unused, copyright) {
        // Display a simple ASCII chart
        outputBuffer = [];
        console.log(chalk.cyan('\n━━━━━━━━━━━━━━━━━━━━━━━━━'));
        console.log(chalk.bold.cyan('Widget Chart: ' + (title || '')));
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━'));

        if (Array.isArray(points) && points.length > 0) {
            const max = Math.max(...points);
            const min = Math.min(...points);
            const height = 5;

            for (let row = height; row >= 0; row--) {
                let line = '';
                const threshold = min + ((max - min) * row / height);
                points.forEach(point => {
                    line += point >= threshold ? '█' : ' ';
                });
                outputBuffer.push(line);
                console.log(chalk.green(line));
            }
        }
        console.log(chalk.cyan('━━━━━━━━━━━━━━━━━━━━━━━━━\n'));
    },

    show_toast: function(message) {
        // Display a toast notification
        console.log(chalk.bgYellow.black(`\n 🔔 Toast: ${message} \n`));
    },

    set_title: function(title) {
        widgetTitle = title;
        console.log(chalk.gray(`[Widget title set to: ${title}]`));
    },

    set_expandable: function() {
        console.log(chalk.gray('[Widget set to expandable]'));
    },

    is_folded: function() {
        return false;
    },

    is_expanded: function() {
        return true;
    },

    set_progress: function(value) {
        console.log(chalk.gray(`[Widget progress: ${(value * 100).toFixed(0)}%]`));
    },

    show_context_menu: function(items) {
        contextMenuItems = items;
        console.log(chalk.yellow('\n📋 Context Menu:'));
        items.forEach((item, idx) => {
            console.log(chalk.yellow(`  ${idx + 1}. ${item}`));
        });
        console.log(chalk.yellow(`  0. Cancel\n`));

        // Return promise that resolves when menu item is selected
        return new Promise((resolve) => {
            contextMenuCallback = resolve;
        });
    }
};

export function selectMenuOption(index) {
    if (contextMenuCallback) {
        contextMenuCallback(index);
        contextMenuCallback = null;
    }
}

export function getOutput() {
    return outputBuffer.join('\n');
}

export function getOutputBuffer() {
    return [...outputBuffer];
}

export function clearOutput() {
    outputBuffer = [];
}

export function hasContextMenu() {
    return contextMenuItems.length > 0;
}

export function getContextMenuItems() {
    return contextMenuItems;
}


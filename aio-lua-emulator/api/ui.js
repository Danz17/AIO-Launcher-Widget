// UI API Emulation for AIO Launcher
import chalk from 'chalk';

let outputBuffer = [];
let contextMenuItems = [];
let contextMenuCallback = null;

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


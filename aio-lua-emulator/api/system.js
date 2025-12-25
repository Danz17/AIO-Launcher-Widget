// System API Emulation for AIO Launcher
import chalk from 'chalk';
import crypto from 'crypto';

// Emulated clipboard storage
let clipboardData = '';

export const system = {
    open_browser: function(url) {
        console.log(chalk.magenta(`\n🌐 Would open browser: ${url}`));
        console.log(chalk.gray('   (In real device, this would open the URL)'));
    },

    toast: function(message) {
        console.log(chalk.yellow(`\n💬 Toast: ${message}`));
    },

    vibrate: function(ms) {
        const duration = ms || 100;
        console.log(chalk.magenta(`\n📳 Vibrate: ${duration}ms`));
        console.log(chalk.gray('   (In real device, this would vibrate)'));
    },

    copy_to_clipboard: function(text) {
        clipboardData = text || '';
        console.log(chalk.magenta(`\n📋 Copied to clipboard: "${text}"`));
        return true;
    },

    clipboard: function() {
        console.log(chalk.gray(`[Clipboard] get() = "${clipboardData}"`));
        return clipboardData;
    },

    share_text: function(text) {
        console.log(chalk.magenta(`\n📤 Share text: "${text}"`));
        console.log(chalk.gray('   (In real device, this would open share dialog)'));
    },

    lang: function() {
        // Return system language (emulated as English)
        return 'en';
    },

    tz: function() {
        // Return timezone string
        return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
    },

    tz_offset: function() {
        // Return timezone offset in minutes
        return new Date().getTimezoneOffset();
    },

    // HMAC-SHA256 for Tuya API signature generation
    hmac_sha256: function(key, message) {
        try {
            const hmac = crypto.createHmac('sha256', key);
            hmac.update(message);
            return hmac.digest('hex').toUpperCase();
        } catch (e) {
            console.error(chalk.red(`✗ HMAC-SHA256 error: ${e.message}`));
            return null;
        }
    },

    // Battery info (emulated)
    battery_info: function() {
        return {
            level: 85,
            isCharging: false,
            temperature: 25
        };
    },

    // Network state (emulated)
    network_state: function() {
        return {
            connected: true,
            type: 'wifi',
            ssid: 'EmulatorWiFi'
        };
    }
};


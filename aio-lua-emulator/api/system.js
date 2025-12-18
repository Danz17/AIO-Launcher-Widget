// System API Emulation for AIO Launcher
import chalk from 'chalk';
import crypto from 'crypto';

export const system = {
    open_browser: function(url) {
        console.log(chalk.magenta(`\n🌐 Would open browser: ${url}`));
        console.log(chalk.gray('   (In real device, this would open the URL)'));
    },
    
    toast: function(message) {
        console.log(chalk.yellow(`\n💬 Toast: ${message}`));
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
    }
};


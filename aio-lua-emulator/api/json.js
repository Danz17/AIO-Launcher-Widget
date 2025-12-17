// JSON API Emulation for AIO Launcher
import chalk from 'chalk';

export const json = {
    decode: function(data) {
        if (!data || data === '') {
            return null;
        }
        
        try {
            // If data is already an object (from mock), use it directly
            const parsed = typeof data === 'string' ? JSON.parse(data) : data;
            console.log(chalk.gray(`   JSON decoded: ${typeof parsed}`));
            // Return as-is - the wrapper will convert JS object to Lua table
            return parsed;
        } catch (e) {
            console.log(chalk.red(`   ✗ JSON decode error: ${e.message}`));
            return null;
        }
    },
    
    encode: function(table) {
        try {
            const encoded = JSON.stringify(table);
            console.log(chalk.gray(`   JSON encoded: ${encoded.length} chars`));
            return encoded;
        } catch (e) {
            console.log(chalk.red(`   ✗ JSON encode error: ${e.message}`));
            return '{}';
        }
    }
};


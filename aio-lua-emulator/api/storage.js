// Storage API Emulation for AIO Launcher
// Provides persistent storage for widget data
import chalk from 'chalk';
import fs from 'fs';
import path from 'path';

const STORAGE_DIR = path.join(process.cwd(), '.widget-storage');
const STORAGE_FILE = path.join(STORAGE_DIR, 'data.json');

// In-memory cache
let storageCache = {};

// Initialize storage
function initStorage() {
    try {
        if (!fs.existsSync(STORAGE_DIR)) {
            fs.mkdirSync(STORAGE_DIR, { recursive: true });
        }
        if (fs.existsSync(STORAGE_FILE)) {
            const data = fs.readFileSync(STORAGE_FILE, 'utf8');
            storageCache = JSON.parse(data);
        }
    } catch (err) {
        console.log(chalk.yellow('[Storage] Initialized with empty cache'));
        storageCache = {};
    }
}

// Save storage to disk
function saveStorage() {
    try {
        if (!fs.existsSync(STORAGE_DIR)) {
            fs.mkdirSync(STORAGE_DIR, { recursive: true });
        }
        fs.writeFileSync(STORAGE_FILE, JSON.stringify(storageCache, null, 2));
    } catch (err) {
        console.log(chalk.red('[Storage] Failed to save: ' + err.message));
    }
}

// Initialize on module load
initStorage();

export const storage = {
    // Get a value from storage
    get: function(key) {
        const value = storageCache[key];
        console.log(chalk.gray(`[Storage] get("${key}") = ${JSON.stringify(value)}`));
        return value !== undefined ? value : null;
    },

    // Set a value in storage
    set: function(key, value) {
        storageCache[key] = value;
        saveStorage();
        console.log(chalk.gray(`[Storage] set("${key}", ${JSON.stringify(value)})`));
        return true;
    },

    // Delete a key from storage
    delete: function(key) {
        if (key in storageCache) {
            delete storageCache[key];
            saveStorage();
            console.log(chalk.gray(`[Storage] delete("${key}")`));
            return true;
        }
        return false;
    },

    // Check if key exists
    has: function(key) {
        return key in storageCache;
    },

    // Get all keys
    keys: function() {
        return Object.keys(storageCache);
    },

    // Clear all storage
    clear: function() {
        storageCache = {};
        saveStorage();
        console.log(chalk.gray('[Storage] cleared'));
        return true;
    },

    // Get all data as object
    getAll: function() {
        return { ...storageCache };
    }
};

// Files API (subset of AIO Launcher files API)
export const files = {
    read: function(filePath) {
        try {
            const data = fs.readFileSync(filePath, 'utf8');
            console.log(chalk.gray(`[Files] read("${filePath}") - ${data.length} bytes`));
            return data;
        } catch (err) {
            console.log(chalk.red(`[Files] read("${filePath}") failed: ${err.message}`));
            return null;
        }
    },

    write: function(filePath, data, append) {
        try {
            if (append) {
                fs.appendFileSync(filePath, data);
            } else {
                fs.writeFileSync(filePath, data);
            }
            console.log(chalk.gray(`[Files] write("${filePath}") - ${data.length} bytes`));
            return true;
        } catch (err) {
            console.log(chalk.red(`[Files] write("${filePath}") failed: ${err.message}`));
            return false;
        }
    },

    exists: function(filePath) {
        const exists = fs.existsSync(filePath);
        console.log(chalk.gray(`[Files] exists("${filePath}") = ${exists}`));
        return exists;
    }
};

export default { storage, files };

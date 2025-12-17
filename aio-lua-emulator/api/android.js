import chalk from 'chalk';

// Mock Android data that can be customized
let mockData = {
    wifi: {
        enabled: true,
        connectedSSID: "MyNetwork",
        networks: [
            { ssid: "MyNetwork", bssid: "00:11:22:33:44:55", rssi: -45, frequency: 5180, capabilities: "WPA2-PSK" },
            { ssid: "NeighborWiFi", bssid: "AA:BB:CC:DD:EE:FF", rssi: -67, frequency: 2437, capabilities: "WPA2-PSK" },
            { ssid: "CoffeeShop_Free", bssid: "11:22:33:44:55:66", rssi: -72, frequency: 2412, capabilities: "Open" },
            { ssid: "SecureNet_5G", bssid: "22:33:44:55:66:77", rssi: -55, frequency: 5240, capabilities: "WPA3-PSK" },
            { ssid: "Guest_Network", bssid: "33:44:55:66:77:88", rssi: -80, frequency: 2462, capabilities: "WPA-PSK" }
        ]
    },
    location: {
        latitude: 40.7128,
        longitude: -74.0060,
        accuracy: 15,
        provider: "gps",
        permissionGranted: true
    },
    battery: {
        level: 75,
        isCharging: false,
        health: "good",
        temperature: 28.5,
        voltage: 3.85
    },
    device: {
        model: "Pixel 7 Pro",
        manufacturer: "Google",
        osVersion: "14",
        sdkVersion: 34,
        screenWidth: 1440,
        screenHeight: 3120,
        density: 3.5
    },
    sensors: {
        accelerometer: { x: 0.1, y: 0.2, z: 9.8 },
        gyroscope: { x: 0.0, y: 0.0, z: 0.0 },
        magnetometer: { x: 25.3, y: -15.7, z: 42.1 },
        light: 450,
        proximity: 5.0
    },
    brightness: 80
};

// Function to update mock data
export function setMockData(category, data) {
    if (mockData[category]) {
        mockData[category] = { ...mockData[category], ...data };
        console.log(chalk.cyan(`📱 Updated Android mock data for: ${category}`));
    }
}

export function getMockData(category) {
    return mockData[category] || null;
}

// Android API Module
export const android = {
    // WiFi Functions
    getWifiList: function() {
        console.log(chalk.blue('📡 Android: Getting WiFi scan results'));
        return mockData.wifi.networks;
    },
    
    getWifiSignal: function() {
        console.log(chalk.blue('📡 Android: Getting WiFi signal strength'));
        const connected = mockData.wifi.networks[0];
        return connected ? connected.rssi : -100;
    },
    
    getConnectedSSID: function() {
        console.log(chalk.blue('📡 Android: Getting connected SSID'));
        return mockData.wifi.connectedSSID;
    },
    
    isWifiEnabled: function() {
        console.log(chalk.blue('📡 Android: Checking WiFi enabled status'));
        return mockData.wifi.enabled;
    },
    
    // Location Functions
    getLocation: function() {
        console.log(chalk.blue('📍 Android: Getting GPS location'));
        return mockData.location;
    },
    
    getLocationPermission: function() {
        console.log(chalk.blue('📍 Android: Checking location permission'));
        return mockData.location.permissionGranted;
    },
    
    // Battery Functions
    getBattery: function() {
        console.log(chalk.blue('🔋 Android: Getting battery status'));
        return mockData.battery;
    },
    
    getBatteryLevel: function() {
        console.log(chalk.blue('🔋 Android: Getting battery level'));
        return mockData.battery.level;
    },
    
    isCharging: function() {
        console.log(chalk.blue('🔋 Android: Checking charging status'));
        return mockData.battery.isCharging;
    },
    
    // Device Info Functions
    getDeviceInfo: function() {
        console.log(chalk.blue('📱 Android: Getting device info'));
        return mockData.device;
    },
    
    getDeviceModel: function() {
        console.log(chalk.blue('📱 Android: Getting device model'));
        return mockData.device.model;
    },
    
    getOSVersion: function() {
        console.log(chalk.blue('📱 Android: Getting OS version'));
        return mockData.device.osVersion;
    },
    
    getScreenSize: function() {
        console.log(chalk.blue('📱 Android: Getting screen size'));
        return {
            width: mockData.device.screenWidth,
            height: mockData.device.screenHeight,
            density: mockData.device.density
        };
    },
    
    // Sensor Functions
    getSensorData: function(sensorType) {
        console.log(chalk.blue(`📊 Android: Getting ${sensorType || 'all'} sensor data`));
        if (sensorType) {
            return mockData.sensors[sensorType] || null;
        }
        return mockData.sensors;
    },
    
    getAccelerometer: function() {
        console.log(chalk.blue('📊 Android: Getting accelerometer data'));
        return mockData.sensors.accelerometer;
    },
    
    getGyroscope: function() {
        console.log(chalk.blue('📊 Android: Getting gyroscope data'));
        return mockData.sensors.gyroscope;
    },
    
    getMagnetometer: function() {
        console.log(chalk.blue('📊 Android: Getting magnetometer data'));
        return mockData.sensors.magnetometer;
    },
    
    getLightSensor: function() {
        console.log(chalk.blue('📊 Android: Getting light sensor data'));
        return mockData.sensors.light;
    },
    
    getProximitySensor: function() {
        console.log(chalk.blue('📊 Android: Getting proximity sensor data'));
        return mockData.sensors.proximity;
    },
    
    // Screen Brightness
    getScreenBrightness: function() {
        console.log(chalk.blue('☀️ Android: Getting screen brightness'));
        return mockData.brightness;
    },
    
    setScreenBrightness: function(level) {
        console.log(chalk.blue(`☀️ Android: Setting screen brightness to ${level}%`));
        mockData.brightness = Math.min(100, Math.max(0, level));
        return true;
    },
    
    // Utility Functions
    toast: function(message) {
        console.log(chalk.yellow(`🍞 Android Toast: ${message}`));
    },
    
    vibrate: function(duration) {
        console.log(chalk.magenta(`📳 Android: Vibrating for ${duration}ms`));
    }
};


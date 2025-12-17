@echo off
REM Test script for the emulator (Windows)

echo Testing AIO Lua Emulator with v10 MikroTik script...
echo.

REM Test 1: Basic run with mocks
echo Test 1: Running with mock data...
node emulator.js ..\Mikrotik\mikrotik_widget_v10.lua --mock mocks\mikrotik_success.json

echo.
echo Test complete!
pause


# Changelog

All notable changes to the AIO Launcher Widget Emulator and Widget Collection.

---

## [2.0.0] - 2024-12-25

### Added - Emulator
- AI Script Inspector with Groq API integration
- Comprehensive API reference in `docs/API_REFERENCE.md`
- Logging system for AI analysis (`logs/` directory)
- Strict API validation to prevent broken code suggestions

### Added - Widgets
- **device_monitor.lua** - Battery, WiFi, brightness, device info
- **weather.lua** - OpenWeatherMap current + 3-day forecast
- **pihole_monitor.lua** - Pi-hole DNS blocking stats
- **prayer_times.lua** - Islamic prayer times (Aladhan API)
- **quick_notes.lua** - Simple note-taking with history
- **stocks.lua** - Stock ticker (Yahoo Finance)
- **speedtest.lua** - Internet speed test (Cloudflare)

### Changed
- Consolidated MikroTik widgets into single `mikrotik.lua`
- Removed broken `tuya_devices.lua` (HMAC auth too complex)
- Improved AI prompt to prevent non-existent API usage

### Fixed
- AI Inspector no longer suggests `http:set_headers()` for emulator
- URL-embedded authentication works in both emulator and real device

---

## [1.0.0] - 2024-12-24

### Added - Emulator
- Visual emulator with Monaco editor
- 2-column layout (Editor + Preview)
- Bottom debug panel (HTTP, Storage, Console, Monitor)
- Upload widget persistence
- Delete widget functionality
- Auto-execution on script load
- MikroTik API proxy endpoints
- Settings modal (MikroTik credentials, API keys)

### Added - Widgets
- **mikrotik.lua** - Router monitoring (CPU, RAM, LTE, clients)
- **wifi_analyzer.lua** - WiFi network scanner
- **synology_nas.lua** - NAS system monitoring
- **surveillance.lua** - Synology camera status
- **crypto_prices.lua** - Cryptocurrency prices (Binance)
- **enpass.lua** - Password manager status

---

## Future Ideas

### Widget Ideas

| Widget | API | Priority | Notes |
|--------|-----|----------|-------|
| **Home Assistant** | HA REST API | High | Entity control, automations |
| **Plex/Jellyfin** | Media server API | Medium | Now playing, library stats |
| **UPS Monitor** | NUT/APC API | Medium | Battery, load, runtime |
| **Calendar** | Google Calendar API | Medium | Today's events, reminders |
| **Countdown** | Local | Low | Days until event |
| **Pomodoro Timer** | Local | Low | Work/break timer |
| **Habit Tracker** | Local | Low | Daily habits checkoff |
| **Server Monitor** | SSH/API | Medium | Multi-server status |
| **Docker Monitor** | Docker API | Medium | Container status |
| **Git Activity** | GitHub API | Low | Repo stats, commits |

### Emulator Improvements

| Feature | Priority | Notes |
|---------|----------|-------|
| **Real `http:set_headers()`** | High | Match real AIO API |
| **`prefs` module** | High | Persistent settings dialog |
| **`files:*` module** | Medium | File read/write support |
| **Widget resize** | Medium | Test different widget sizes |
| **Dark/Light theme** | Low | Match AIO themes |
| **Export to .lua** | Low | Download widget file |
| **Widget gallery** | Low | Browse/preview all widgets |
| **Mock data editor** | Medium | Customize android.* values |
| **Alarm simulation** | Low | Test `on_alarm()` callback |

### API Gaps (Emulator vs Real Device)

| API | Emulator | Real AIO | Action Needed |
|-----|----------|----------|---------------|
| `http:set_headers()` | Mock | Works | Implement properly |
| `prefs` module | Missing | Works | Add prefs support |
| `files:read/write` | Missing | Works | Add file storage |
| `system:exec()` | Missing | Works | Security risk |
| `apps:launch()` | Missing | Works | Add mock |
| `ui:show_chart()` | Basic | Full | Improve chart rendering |

### Known Issues

1. **Speedtest accuracy** - Download timing in Lua may not be precise
2. **Stock data delay** - Yahoo Finance has 15-min delay
3. **Prayer times cache** - Should cache daily to reduce API calls
4. **Quick notes input** - Real AIO has input dialog, emulator doesn't

---

## Contributing

1. Fork the repository
2. Create widget in `Widgets/` folder
3. Test in emulator at `http://localhost:3000`
4. Submit pull request

### Widget Guidelines

- Use 2-space indentation
- Include meta tags (name, description, author, type)
- Handle errors with `pcall()` for JSON decoding
- Use URL-embedded auth for HTTP (emulator compatible)
- Add context menu for settings/options
- Follow existing widget patterns

---

## Resources

- **Official AIO Scripts:** [github.com/zobnin/aiolauncher_scripts](https://github.com/zobnin/aiolauncher_scripts)
- **AIO Launcher:** [aiolauncher.app](https://aiolauncher.app)
- **Lua 5.2 Reference:** [lua.org/manual/5.2](https://www.lua.org/manual/5.2/)

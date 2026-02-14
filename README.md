# BusBoard NL

Personalized arrival board for **Metrobus** — St. John's, Mount Pearl & Paradise, NL.

## What It Does

- **Select a stop** by entering its 4-digit ID or using **Near Me** GPS discovery
- **View an arrival board** showing all upcoming departures: route number, headsign, scheduled time, and "in X min" countdown
- **Live ETA adjustments** via TimeTrack — shows AHEAD / BEHIND / ON TIME badges when live data is available
- **Auto-refresh** with configurable interval (15–120s), foreground-only to conserve battery
- **Pull-to-refresh** for immediate updates

## Data Sources

| Source | URL | Purpose |
|--------|-----|---------|
| GTFS Schedule ZIP | `metrobus.com/gtfs.asp` | Static schedule (stops, routes, trips, stop times, calendars) |
| TimeTrack JSON | `metrobus.co.ca/api/timetrack/json/` | Live vehicle positions + schedule adherence |

## Caching & Refresh Policy

- **GTFS ZIP**: Downloaded to app documents dir, cached for **7 days**. Manual re-download available in Settings.
- **Live data**: Polled every **30s** by default (configurable 15–120s). Only runs when the app is **foregrounded**.
- **Settings**: Persisted via SharedPreferences (selected stop, refresh interval, last update).

## Architecture

```
lib/
  main.dart / app.dart              → Entry point & Material theme
  routing/router.dart               → GoRouter (3 routes)
  data/
    gtfs/                           → GTFS download, parse, models, time utils
    realtime/                       → TimeTrack API client & models
  domain/
    arrival/                        → Arrival computation & live merging
    location/                       → Nearest stop (haversine)
  ui/
    stop_picker/                    → Stop ID entry + Near Me list
    board/                          → Arrival board + row tiles
    settings/                       → Refresh interval & GTFS management
  state/providers.dart              → Riverpod providers
  utils/app_lifecycle.dart          → Foreground/background observer
```

## How to Run

```bash
# Install dependencies
flutter pub get

# Run on connected device / emulator
flutter run

# Run tests
flutter test
```

## Key Technical Notes

- **GTFS times >24:00:00** are handled correctly (e.g., `25:10:00` = 1:10 AM next day)
- **Live ETA**: `predicted = scheduled − sched_difference_mins` (positive diff = bus ahead = arrives earlier)
- **Timezone**: App uses device local time; designed for America/St_Johns
- **No database**: All GTFS data is held in-memory via indexed maps for fast lookup

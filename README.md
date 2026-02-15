# BusBoard NL

Personalized arrival board and live bus tracking map for **Metrobus** — St. John's, Mount Pearl & Paradise, NL.

## What It Does

### Arrival Board
- **Select a stop** by entering its 4-digit ID or using **Near Me** GPS discovery
- **View an arrival board** showing all upcoming departures: route number, headsign, scheduled time, and "in X min" countdown
- **Live ETA adjustments** via TimeTrack — shows AHEAD / BEHIND / ON TIME badges when live data is available
- **Pull-to-refresh** for immediate updates

### Live Map
- **Real-time bus positions** as red markers on a MapLibre map
- **Smooth animation** — buses glide along route shapes between GPS updates using interpolation and dead-reckoning
- **Tap a bus** to see route info and draw its full route shape on the map (persists while you pan/zoom)
- **Tap a stop** to see stop info and set it as your selected stop
- **Route filter** — filter visible buses by route number
- **Legend** — collapsible overlay explaining map symbols
- **Center on selected stop** — quick-navigate button when you've drifted far on the map

### Settings
- **Configurable refresh interval** (5–60s, default 5s) — controls both map and board polling
- **GTFS data management** — force re-download of schedule data
- **Selected stop** persisted across sessions

## Data Sources

| Source | URL | Purpose |
|--------|-----|---------|
| GTFS Schedule ZIP | `metrobus.com/gtfs.asp` | Static schedule (stops, routes, trips, stop times, shapes, calendars) |
| TimeTrack JSON | `metrobus.co.ca/api/timetrack/json/` | Live vehicle positions, speed, heading, schedule adherence |

### TimeTrack API Data
Each vehicle reports: lat/lon, speed (km/h), compass heading, route number, headsign, GTFS trip ID, schedule deviation. GPS hardware on buses updates every ~15 seconds (variable per bus, 9–60s observed).

## Caching & Refresh Policy

- **GTFS ZIP**: Downloaded to app documents dir, cached for **7 days**. Manual re-download available in Settings.
- **Live data**: Polled every **5s** by default (configurable 5–60s). Applies to both the arrival board and map bus tracking.
- **Settings**: Persisted via SharedPreferences (selected stop, refresh interval, last GTFS update).

## Bus Motion Engine

The motion engine (`bus_motion_engine.dart`) provides smooth bus animation between GPS updates:

- **Route shape snapping** — raw GPS positions snapped to GTFS route geometry
- **Shape fallback matching** — resolves routes by route number + headsign when GTFS trip ID is unavailable
- **Interpolation** — linear interpolation along route shapes between two GPS observations
- **Dead-reckoning** — extrapolates forward using segment average speed for up to 35s beyond the last GPS point
- **Speed decay** — gradually reduces extrapolation speed (100% → 65%) to avoid overshooting
- **Stop heuristic** — gentle slowdown (60–100%) near bus stops, never a full stop (most stops are skipped)
- **Blend smoothing** — 600ms cubic ease-out transition when new GPS data corrects a predicted position
- **Backward movement** — allows up to 120m backward correction (blend makes it look natural)
- **Outlier rejection** — rejects GPS points implying speeds >140 km/h

## Architecture

```
lib/
  main.dart / app.dart              → Entry point & Material theme
  routing/router.dart               → GoRouter (bottom nav: Board, Map, Settings)
  data/
    gtfs/                           → GTFS download, parse, models, time utils
    realtime/                       → TimeTrack API client & models
  domain/
    arrival/                        → Arrival computation & live merging
    location/                       → Nearest stop (haversine)
    map/
      bus_motion_engine.dart        → Interpolation, dead-reckoning, blend smoothing
      bus_tracking_state.dart       → Per-bus state (position, route, status)
      bus_observation.dart          → Individual GPS observation
      shape_matcher.dart            → Snap GPS to route geometry
  ui/
    stop_picker/                    → Stop ID entry + Near Me list
    board/                          → Arrival board + row tiles
    map/
      map_screen.dart               → MapLibre map with bus/stop layers
      bus_bottom_sheet.dart         → Bus info sheet (route, speed, status)
      stop_bottom_sheet.dart        → Stop info sheet with "set as stop" action
    settings/                       → Refresh interval & GTFS management
  state/providers.dart              → Riverpod providers (polling stream, engine, settings)
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
- **MapLibre GeoJSON bug**: `setGeoJsonSource` doesn't re-render circle layers reliably on this stack — buses are rendered with circle annotations.
- **GPS update cadence**: Bus GPS hardware reports every ~15s (most common: 15–16s, range: 9–78s). App polls every 5s to catch updates promptly.

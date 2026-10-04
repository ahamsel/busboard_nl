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
- **Measurement-time aware timing** — uses `position_time_seconds` (bus measurement time), not fetch time, for motion deltas
- **Interpolation** — interpolation/extrapolation primarily in route-progress space (meters along GTFS shape)
- **Kalman progress filter** — 1D position/velocity filter per bus for smoother prediction between updates
- **Adaptive measurement trust** — measurement noise scales with snap quality (larger snap distance = less trust)
- **Auto-adjust mode** — bounded on-device tuning of Kalman and blend parameters using live innovation/correction metrics
- **Dead-reckoning** — extrapolates forward up to 35s beyond the last GPS point with decay and stop-aware slowdown
- **Road-follow blend smoothing** — correction blend follows route geometry through turns (avoids straight-line glides)
- **Anti-typewriter clamp** — active buses are visually monotonic (no tiny backward jitter); true backtracking still allowed
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

## Building

- Android builds need JDK 21 (maplibre_gl 0.27 targets Java 21). Point Gradle at it, for example with `JAVA_HOME` and `GRADLE_OPTS=-Dorg.gradle.java.home=<jdk21>`.
- The iOS deployment target is 15.0 (the minimum Flutter 3.47 supports).
- Release builds are signed from `android/key.properties`, which is not checked in.

## How to Run

```bash
# Install dependencies
flutter pub get

# Run on connected device / emulator
flutter run

# Run tests
flutter test

# Run movement replay harness (turns, lag, noise, stability metrics)
flutter test test/map/bus_motion_replay_harness_test.dart

# Capture the app's real production live-data chain (example: 15 minutes)
dart run tool/capture_timetrack_snapshots.dart \
  --interval 5 \
  --duration 900 \
  --out test/fixtures/timetrack/capture.json

# Inspect raw physical IDs, duplicate assignments, teleports, and A→B→A
# ping-pongs before replaying what the app renders.
dart run tool/analyze_live_vehicle_trace.dart \
  test/fixtures/timetrack/capture.json

# Replay captured snapshots through BusMotionEngine
BUS_MOTION_CAPTURE_PATH=test/fixtures/timetrack/capture.json \
flutter test test/map/bus_motion_snapshot_replay_test.dart

# Optional: write replay metrics JSON (for commit-to-commit trend tracking)
BUS_MOTION_CAPTURE_PATH=test/fixtures/timetrack/capture.json \
BUS_MOTION_METRICS_OUT=build/bus_motion/replay_metrics.json \
flutter test test/map/bus_motion_snapshot_replay_test.dart
```

## Key Technical Notes

- **GTFS times >24:00:00** are handled correctly (e.g., `25:10:00` = 1:10 AM next day)
- **Live ETA**: `predicted = scheduled − sched_difference_mins` (positive diff = bus ahead = arrives earlier)
- **Timezone**: App uses device local time; designed for America/St_Johns
- **No database**: All GTFS data is held in-memory via indexed maps for fast lookup
- **MapLibre GeoJSON bug**: `setGeoJsonSource` doesn't re-render circle layers reliably on this stack — buses are rendered with circle annotations.
- **GPS update cadence**: Bus GPS hardware reports periodically; the app polls every 5s to catch new observations promptly.

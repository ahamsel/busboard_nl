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

## Bus Motion

Buses on the map are drawn a little behind live and glide along their route between real GPS fixes (`lib/domain/map/`, pure Dart):

- **`BusTrackStore`** — one track per physical vehicle ID, built from each poll. Fixes are snapped to the GTFS route shape with a progress hint, so a bus on an out-and-back route stays on its own pass. Duplicate or out-of-order GPS timestamps are ignored; a bus with no new fix for 90 s is stale, and its track is dropped after 5 min.
- **`DelayedTrackRenderer`** — draws each bus at `now − D`, interpolated by distance along the shape between two real fixes. D is latency-aware (feed lag plus about one fix interval, clamped to 8–30 s, typically about 25 s) and eased in at 0.1 s per second.
- **Never backward** — a bus never moves backward along the same trip; when GPS runs backward it holds.
- **Edge cases** — geographic interpolation across a trip change and for off-route buses (over 150 m from the shape); extrapolation for at most 5 s past the newest fix, then hold; drawn motion is capped at 30 m/s.
- **Replay fixtures** — `test/map/motion_replay_test.dart` replays recorded captures from `test/fixtures/timetrack/` through the pipeline (see the README there).

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
      route_geometry.dart           → Snap to shapes, poses along them, stop/timetable hints
      bus_track.dart                → GPS fixes and tracks per vehicle
      bus_track_store.dart          → Ingests each poll into per-vehicle tracks
      delayed_track_renderer.dart   → Where to draw each bus now (about 25 s behind, gliding)
      bus_tracking_state.dart       → Per-bus snapshot for the map and sheet
      shape_matcher.dart            → Snap GPS to route geometry
  ui/
    stop_picker/                    → Stop ID entry + Near Me list
    board/                          → Arrival board + row tiles
    map/
      map_screen.dart               → MapLibre map with bus/stop layers
      bus_bottom_sheet.dart         → Bus info sheet (route, speed, status)
      stop_bottom_sheet.dart        → Stop info sheet with "set as stop" action
    settings/                       → Refresh interval & GTFS management
  state/providers.dart              → Riverpod providers (polling stream, track store, renderer, settings)
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

# Replay recorded captures through the motion pipeline
flutter test test/map/motion_replay_test.dart

# Capture the app's real production live-data chain (example: 15 minutes)
dart run tool/capture_timetrack_snapshots.dart \
  --interval 5 \
  --duration 900 \
  --out /tmp/capture.json

# Inspect raw physical IDs, duplicate assignments, teleports, and A→B→A
# ping-pongs before replaying what the app renders.
dart run tool/analyze_live_vehicle_trace.dart \
  /tmp/capture.json
```

## Key Technical Notes

- **GTFS times >24:00:00** are handled correctly (e.g., `25:10:00` = 1:10 AM next day)
- **Live ETA**: `predicted = scheduled − sched_difference_mins` (positive diff = bus ahead = arrives earlier)
- **Timezone**: App uses device local time; designed for America/St_Johns
- **No database**: All GTFS data is held in-memory via indexed maps for fast lookup
- **MapLibre GeoJSON bug**: `setGeoJsonSource` doesn't re-render circle layers reliably on this stack — buses are rendered with circle annotations.
- **GPS update cadence**: Bus GPS hardware reports periodically; the app polls every 5s to catch new observations promptly.

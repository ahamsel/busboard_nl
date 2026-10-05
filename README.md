# BusBoard NL

Personalized arrival board and live bus tracking map for **Metrobus** — St. John's, Mount Pearl & Paradise, NL.

## What It Does

### Arrival Board
- **Select a stop** by entering its 4-digit ID or using **Near Me** GPS discovery
- **View an arrival board** showing all upcoming departures: route number, headsign, scheduled time, and "in X min" countdown
- **Live ETA adjustments** via TimeTrack — shows AHEAD / BEHIND / ON TIME badges when live data is available
- **Pull-to-refresh** for immediate updates

### Live Map
- **Harbour map styles** — quiet light and dark basemaps built on OpenFreeMap (no API key), following the app theme or the Settings map-theme override
- **Real-time bus positions** as route-badge markers (the route's number on its colour) with a heading notch; a bus with no recent fix turns grey
- **Smooth animation** — buses are drawn a little behind live and glide along route shapes between GPS updates (see Bus Motion)
- **Your stop** is marked with a brand-blue star; other stops appear as small dots once you zoom in
- **Stop and route chips** — the top-left chip names your stop and opens the stop picker; the top-right chip opens the route filter, a card of route badges to show only the routes you choose
- **My location** control to recentre on where you are
- **One floating sheet** that follows what you tap: your stop's next arrivals by default, a stop card (arrivals, *Set as my stop*, *Open board*) when you tap a stop, and a bus card (route, destination, early/late, technical details) when you tap a bus; drag it between peek, half and full
- **Map credit link** — "© OpenStreetMap · OpenFreeMap" opens the full credits
- **Follow mode** — follow one bus from **Follow** on a bus card, or by tapping a live row on the Board
  - the bus's route line is drawn in the route colour (the part already driven fades), the followed bus is drawn larger and the other buses fade
  - the camera keeps the bus and your stop in view and closes in as the bus nears; a pan or zoom pauses it and shows a "Back to bus" chip that resumes it
  - the follow card shows the stops to your stop, a stop strip (driven, the bus, upcoming, your stop) and *Stop following* and *See all stops* (a timeline of the rest of the trip with ETAs)
  - it ends on its own: "Arrived at …" and 10 s later, a toast when the bus passes your stop or its trip ends, and "Last seen …" when the bus drops out of the feed (a toast after 5 min); it never switches to another bus
  - a bus that never shows up on the map ("Finding bus …") ends the follow with a toast after 60 s
  - the feed relabels trips on the timetable clock, so a new trip ID alone does not end it: it keeps the old trip while the bus is still driving it, and moves to the new trip when that one serves your stop
  - after the phone has been locked, nothing ends until the first fresh poll

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
      heading_smoother.dart         → Eases bus heading changes so notches don't flick
      shape_matcher.dart            → Snap GPS to route geometry
  ui/
    stop_picker/                    → Stop ID entry + Near Me list
    board/                          → Arrival board + row tiles
    map/
      map_screen.dart               → The Map tab: chips, my-location, credit link, one floating sheet
      map_view.dart                 → MapLibre widget behind an injectable builder (tests stub it)
      map_surface.dart              → The slice of MapLibre the screen uses (camera, sources, layers), faked in tests
      map_layers.dart               → Stop, your-stop and bus layers; bus markers for each frame
      marker_images.dart            → Draws the badge, notch and star marker images
      map_style.dart                → Picks the light or dark Harbour style asset
      map_hit_test.dart             → Tap to nearest bus or stop
      stop_card.dart                → Stop card and arrivals list
      bus_card.dart                 → Bus card and technical details
      my_stop_card.dart             → Your-stop card (the sheet's default)
      route_filter_card.dart        → Floating route filter
    settings/                       → Refresh interval & GTFS management
  state/providers.dart              → Riverpod providers (polling stream, track store, renderer, settings)
  state/map_providers.dart          → Map selection, route filter, per-stop arrivals, app foreground state
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

# Regenerate the two map styles from OpenFreeMap Positron
dart run tool/build_map_styles.dart

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
- **GPS update cadence**: Bus GPS hardware reports periodically; the app polls every 5s to catch new observations promptly.

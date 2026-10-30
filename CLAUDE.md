# BusBoard NL – working rules for Claude Code

Flutter app (iOS + Android) for Metrobus riders in St. John's, Mount Pearl and Paradise: arrival board, live bus map, follow-a-bus, trip planner, arrival and service alerts. Live on the App Store and Google Play, so every change ships to real riders.

## How we work
- Every non-trivial feature starts as a spec in `docs/superpowers/specs/`, then a step-by-step plan in `docs/superpowers/plans/`, then build notes in `docs/superpowers/notes/`. Read the matching spec and plan before writing code; update the notes as you go.
- Work on a `claude/<topic>` branch and open a PR. Small, reviewable commits; the human reviews every diff.
- Ask before changing store listings, signing, bundle IDs, permissions or anything under `store/`.

## Commands
- `flutter pub get`, `flutter run`, `flutter test`
- Motion pipeline replay: `flutter test test/map/motion_replay_test.dart`
- Map styles: `dart run tool/build_map_styles.dart`
- Capture live data: `dart run tool/capture_timetrack_snapshots.dart --interval 5 --duration 900 --out /tmp/capture.json`, then inspect with `dart run tool/analyze_live_vehicle_trace.dart /tmp/capture.json`
- Android builds need JDK 21; iOS deployment target is 15.0.

## Code map
- `lib/data/gtfs/` GTFS download, parse, models; `lib/data/realtime/` TimeTrack client
- `lib/domain/` arrivals, nearest stop, and `domain/map/` (pure Dart motion pipeline: route geometry, bus tracks, delayed renderer)
- `lib/ui/` screens (board, map, stop picker, settings); `lib/state/` Riverpod providers; `lib/routing/` GoRouter

## Rules that must not break
- Domain logic stays pure Dart (no Flutter imports in `lib/domain/`) so it can be tested without a device.
- A bus never moves backward along the same trip on the map. Duplicate or out-of-order GPS fixes are ignored.
- GTFS times past 24:00:00 belong to the next service day. The app uses device local time (America/St_Johns).
- Live ETA: predicted = scheduled - sched_difference_mins (positive = bus ahead).
- `MapView` sits behind an injectable builder; widget tests stub it. Keep it that way.
- Any change to motion or live data gets a test, ideally a replay of a recorded capture in `test/fixtures/timetrack/`.

## Before calling something done
- `flutter test` passes and `flutter analyze` is clean.
- Check the change on a real device for anything visual or map-related.
- Never commit signing files (`android/key.properties`, keystores), Firebase config files or API keys.

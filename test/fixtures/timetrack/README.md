# TimeTrack Capture Fixtures

This folder is for local replay fixtures captured from:

- `https://www.metrobus.co.ca/api/timetrack/json/`

Capture command:

```bash
dart run tool/capture_timetrack_snapshots.dart \
  --interval 5 \
  --duration 900 \
  --out test/fixtures/timetrack/capture.json
```

Replay command:

```bash
BUS_MOTION_CAPTURE_PATH=test/fixtures/timetrack/capture.json \
flutter test test/map/bus_motion_snapshot_replay_test.dart
```

Replay + metrics artifact:

```bash
BUS_MOTION_CAPTURE_PATH=test/fixtures/timetrack/capture.json \
BUS_MOTION_METRICS_OUT=build/bus_motion/replay_metrics.json \
flutter test test/map/bus_motion_snapshot_replay_test.dart
```

Optional frame cap for faster CI/local iteration:

```bash
BUS_MOTION_CAPTURE_PATH=test/fixtures/timetrack/capture.json \
BUS_MOTION_MAX_FRAMES=120 \
flutter test test/map/bus_motion_snapshot_replay_test.dart
```

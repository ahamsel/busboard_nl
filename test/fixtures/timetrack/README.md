# TimeTrack Capture Fixtures

This folder is for local replay fixtures captured from the same production
live-data chain as the app: GTFS-Realtime first, then the public Fleet View and
legacy TimeTrack fallbacks.

Capture command:

```bash
dart run tool/capture_timetrack_snapshots.dart \
  --interval 5 \
  --duration 900 \
  --out test/fixtures/timetrack/capture.json
```

Replay command:

```bash
dart run tool/analyze_live_vehicle_trace.dart \
  test/fixtures/timetrack/capture.json

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

## Replay fixtures

`test/map/motion_replay_test.dart` replays every folder here that holds a
`capture.json` and a `gtfs/` directory through the map motion pipeline, so a
new fixture needs only its folder. Metrobus open data.

Build one from a capture and the GTFS folder it was recorded against:

```bash
python3 tool/build_replay_fixture.py CAPTURE.json GTFS_DIR \
  test/fixtures/timetrack/replay_YYYY-MM-DD_label \
  --start 0 --minutes 10 [--vehicles 2443,2573]
```

`--start` and `--minutes` pick the window (minutes from the first frame).
The tool keeps only the GTFS rows the kept vehicles' trips need
(`calendar.txt` and `calendar_dates.txt` if the feed has them) and writes a
`note` ("Metrobus open data. ...") into `capture.json`, ahead of any note the
capture already had. Keep fixtures under a few MB.

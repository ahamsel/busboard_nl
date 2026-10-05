import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/replay_clock.dart';

/// Replays every recorded capture under test/fixtures/timetrack/ through the
/// motion pipeline at the map's 120 ms frame rate and checks spec §1:
/// never backward on a trip, never faster than the fixes imply, and moving
/// whenever the fixes on both sides show movement. Measured inside the
/// renderer (progress along the shape), not by projecting drawn points.
void main() {
  final dirs = Directory('test/fixtures/timetrack')
      .listSync()
      .whereType<Directory>()
      .where((d) => File('${d.path}/capture.json').existsSync() && Directory('${d.path}/gtfs').existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('at least one replay fixture is present', () => expect(dirs, isNotEmpty));

  for (final dir in dirs) {
    test('replay ${dir.path.split('/').last}', () async {
      final repo = GtfsRepository();
      await repo.loadFromDirectory('${dir.path}/gtfs');
      final geometry = RouteGeometry(repo);
      final store = BusTrackStore(geometry);
      final renderer = DelayedTrackRenderer(geometry);
      final json = jsonDecode(File('${dir.path}/capture.json').readAsStringSync()) as Map<String, dynamic>;
      final rawFrames = (json['frames'] as List).cast<Map<String, dynamic>>();
      // The store reads feed times as local wall-clock; put the captured UTC
      // fetch times on that wall clock so the replay is timezone independent.
      final clock = ReplayClock.fromFrames(rawFrames);
      final frames = [
        for (final f in rawFrames)
          if (f['status_code'] == 200)
            (clock.toLocal(DateTime.parse(f['fetch_time'] as String)),
             [for (final v in (f['vehicles'] as List)) TimeTrackVehicle.fromJson(v as Map<String, dynamic>)]),
      ];
      expect(frames.length, greaterThan(20));

      const step = Duration(milliseconds: 120);
      final last = <String, ({String? trip, double? p, double lat, double lon})>{};
      final backward = <String>[];
      var movingFrames = 0;
      var advancedFrames = 0;
      var maxKmh = 0.0;
      var maxImpliedKmh = 0.0;
      var renderedFrames = 0;
      final buses = <String>{};

      for (var i = 0; i < frames.length; i++) {
        final (poll, vehicles) = frames[i];
        store.ingest(vehicles, poll);
        final end = i + 1 < frames.length ? frames[i + 1].$1 : poll.add(const Duration(seconds: 5));
        for (var t = poll; t.isBefore(end); t = t.add(step)) {
          for (final track in store.tracks.values) {
            final bus = renderer.render(track, t);
            renderedFrames++;
            buses.add(bus.vehicleId);
            final prev = last[bus.vehicleId];
            last[bus.vehicleId] = (trip: bus.tripId, p: bus.progress, lat: bus.lat, lon: bus.lon);
            if (prev == null) continue;
            final meters = NearestStopService.haversineDistance(prev.lat, prev.lon, bus.lat, bus.lon);
            maxKmh = math.max(maxKmh, meters / 0.12 * 3.6);
            if (prev.trip == bus.tripId && prev.p != null && bus.progress != null) {
              if (bus.progress! < prev.p! - 0.01) backward.add('${bus.vehicleId} ${prev.p!.round()}→${bus.progress!.round()}');
              // "Moving" = the two fixes around this frame are on the same
              // trip and more than 20 m apart along it.
              final fixes = track.fixes;
              // The renderer draws at now minus its slewed delay, so measure
              // against that rather than the unslewed target.
              final at = t.subtract(renderer.currentDelayFor(track.vehicleId) ?? renderer.delayFor(track));
              for (var k = 0; k + 1 < fixes.length; k++) {
                final a = fixes[k], b = fixes[k + 1];
                if (!at.isBefore(a.gpsTime) && at.isBefore(b.gpsTime) &&
                    a.tripId == b.tripId && a.progress != null && b.progress != null &&
                    b.progress! - a.progress! > 20) {
                  movingFrames++;
                  if (bus.progress! > prev.p!) advancedFrames++;
                  final secs = b.gpsTime.difference(a.gpsTime).inMilliseconds / 1000.0;
                  maxImpliedKmh = math.max(maxImpliedKmh, (b.progress! - a.progress!) / secs * 3.6);
                }
              }
            }
          }
        }
      }

      // ignore: avoid_print
      print('REPLAY_METRICS ${dir.path.split('/').last}: poll frames=${frames.length} rendered frames=$renderedFrames '
          'buses=${buses.length} backward=${backward.length} moving=$movingFrames advanced=$advancedFrames '
          'ratio=${movingFrames == 0 ? 'n/a' : (advancedFrames / movingFrames).toStringAsFixed(4)} '
          'maxDrawnKmh=${maxKmh.toStringAsFixed(1)} maxImpliedKmh=${maxImpliedKmh.toStringAsFixed(1)}');

      expect(backward, isEmpty, reason: backward.take(5).join('\n'));
      expect(movingFrames, greaterThan(0));
      expect(advancedFrames / movingFrames, greaterThanOrEqualTo(0.95),
          reason: '$advancedFrames of $movingFrames moving frames advanced');
      // Geographic hops at trip changes and off-route stretches are allowed
      // up to the fastest implied segment speed plus margin.
      expect(maxKmh, lessThan(math.max(maxImpliedKmh, 60) * 1.5 + 20),
          reason: 'max drawn ${maxKmh.round()} km/h, max implied ${maxImpliedKmh.round()} km/h');
    });
  }
}

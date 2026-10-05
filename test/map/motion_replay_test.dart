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
/// never backward on a trip, never faster than the continuity limit (30 m/s
/// plus 5%), and moving whenever the fixes on both sides show movement.
/// Backward motion is checked twice: on the progress the renderer reports,
/// and on every frame (progress or not) by projecting the drawn point onto
/// the trip's shape.
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
      // Backward check on every frame: the drawn point projected on the shape.
      final projected = <String, ({String? trip, double? along})>{};
      final backwardProjected = <String>[];

      for (var i = 0; i < frames.length; i++) {
        final (poll, vehicles) = frames[i];
        store.ingest(vehicles, poll);
        final end = i + 1 < frames.length ? frames[i + 1].$1 : poll.add(const Duration(seconds: 5));
        for (var t = poll; t.isBefore(end); t = t.add(step)) {
          for (final track in store.tracks.values) {
            final bus = renderer.render(track, t);
            final prev = last[bus.vehicleId];
            last[bus.vehicleId] = (trip: bus.tripId, p: bus.progress, lat: bus.lat, lon: bus.lon);
            final prevProj = projected[bus.vehicleId];
            final proj = _project(geometry, bus, prevProj?.trip == bus.tripId ? prevProj?.along : null);
            final along = proj.along;
            projected[bus.vehicleId] = (trip: bus.tripId, along: along);
            // A projection onto the shape is only evidence of backward motion
            // when the drawn point itself moved that far. Where the shape folds
            // back over itself (a loop, a terminal) the projection can jump by
            // tens of metres while the dot moved centimetres: not a move.
            final moved = prev == null ? 0.0 : NearestStopService.haversineDistance(prev.lat, prev.lon, bus.lat, bus.lon);
            if (!proj.reseeded && along != null && prevProj?.along != null && prevProj!.trip == bus.tripId &&
                along < prevProj.along! - 5 && prevProj.along! - along <= moved + 1) {
              backwardProjected.add('${bus.vehicleId} +${t.difference(frames.first.$1).inSeconds}s ${prevProj.along!.round()}→${along.round()}');
            }
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

      expect(backward, isEmpty, reason: backward.take(5).join('\n'));
      expect(backwardProjected, isEmpty, reason: '${backwardProjected.length} drops over 5 m:\n${backwardProjected.take(5).join('\n')}');
      expect(movingFrames, greaterThan(0));
      expect(advancedFrames / movingFrames, greaterThanOrEqualTo(0.95),
          reason: '$advancedFrames of $movingFrames moving frames advanced');
      // The continuity limiter caps every frame at 30 m/s; allow 5% for the
      // frame-time rounding at poll boundaries.
      expect(maxKmh, lessThanOrEqualTo(30 * 1.05 * 3.6),
          reason: 'max drawn ${maxKmh.round()} km/h, max implied ${maxImpliedKmh.round()} km/h');
    });
  }
}

/// Metres along the bus's trip shape of the drawn point, searched near
/// [near] (the previous frame's value); null without a known shape or when
/// the point is off the shape. A projection that lands outside the search
/// window is another pass over the same road (the window is dropped when
/// nothing fits it): it cannot be a move of one frame, so it is reported as
/// a fresh start (`reseeded`) and never compared.
({double? along, bool reseeded}) _project(RouteGeometry geometry, RenderedBus bus, double? near) {
  final shapeId = geometry.shapeIdForTrip(bus.tripId);
  if (shapeId == null) return (along: null, reseeded: true);
  const back = 100.0, ahead = 200.0;
  final snap = near == null
      ? geometry.snap(bus.lat, bus.lon, shapeId, expectedAlong: bus.progress)
      : geometry.snap(bus.lat, bus.lon, shapeId, expectedAlong: near, minAlong: near - back, maxAlong: near + ahead);
  if (snap == null || snap.perpendicularDistance > RouteGeometry.offRouteMeters) return (along: null, reseeded: true);
  final along = snap.distanceAlongRoute;
  final inWindow = near != null && along >= near - back && along <= near + ahead;
  return (along: along, reseeded: !inWindow);
}

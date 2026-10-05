import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/map/bus_track.dart';
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

  group('the cumulative projected-backward check', () {
    // A drawn path round a bend: the projection falls 50 m (the arc) while
    // the dot is only 35 m (the chord) from where the high water was drawn.
    // The check must see that as backward motion.
    test('flags a 50 m backward step on a curve, though the chord is shorter than the arc', () {
      final check = ProjectedBackwardCheck();
      expect(check.observe(vehicleId: 'v', trip: 't', along: 100, reseeded: true, exempt: false, lat: 47.5600, lon: -52.7500, label: 'start'), isNull);
      expect(check.observe(vehicleId: 'v', trip: 't', along: 200, reseeded: false, exempt: false, lat: 47.5600, lon: -52.7490, label: 'high'), isNull);
      // 35 m north of the high-water point, 50 m back along the route.
      final flagged = check.observe(vehicleId: 'v', trip: 't', along: 150, reseeded: false, exempt: false, lat: 47.5600 + 35 / 110574, lon: -52.7490, label: 'back');
      expect(flagged, isNotNull);
      expect(flagged, contains('200 → 150'));
    });

    test('ignores a projection that falls while the dot did not move (a fold in the shape)', () {
      final check = ProjectedBackwardCheck();
      check.observe(vehicleId: 'v', trip: 't', along: 200, reseeded: true, exempt: false, lat: 47.56, lon: -52.749, label: 'high');
      expect(check.observe(vehicleId: 'v', trip: 't', along: 160, reseeded: false, exempt: false, lat: 47.56 + 1 / 110574, lon: -52.749, label: 'fold'), isNull);
    });

    test('exempt glides, other trips and reseeded frames never count', () {
      final check = ProjectedBackwardCheck();
      check.observe(vehicleId: 'v', trip: 't', along: 200, reseeded: true, exempt: false, lat: 47.56, lon: -52.749, label: 'high');
      final far = 47.56 + 80 / 110574;
      expect(check.observe(vehicleId: 'v', trip: 't', along: 100, reseeded: false, exempt: true, lat: far, lon: -52.749, label: 'glide'), isNull);
      check.observe(vehicleId: 'v', trip: 't', along: 200, reseeded: true, exempt: false, lat: 47.56, lon: -52.749, label: 'high');
      expect(check.observe(vehicleId: 'v', trip: 'other', along: 100, reseeded: false, exempt: false, lat: far, lon: -52.749, label: 'trip'), isNull);
      check.observe(vehicleId: 'v', trip: 't', along: 200, reseeded: true, exempt: false, lat: 47.56, lon: -52.749, label: 'high');
      expect(check.observe(vehicleId: 'v', trip: 't', along: 100, reseeded: true, exempt: false, lat: far, lon: -52.749, label: 'reseed'), isNull);
    });
  });

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
      // Backward check on every frame: the drawn point projected on the shape,
      // against the vehicle's high-water projection on its trip.
      final projected = <String, ({String? trip, double? along})>{};
      final backwardCheck = ProjectedBackwardCheck();
      final lastLatest = <String, DateTime>{};
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
            final proj = _project(geometry, bus, bus.progress ?? (prevProj?.trip == bus.tripId ? prevProj?.along : null));
            final along = proj.along;
            projected[bus.vehicleId] = (trip: bus.tripId, along: along);
            // Cumulative: the projection falling more than 5 m below the high
            // water on this trip is backward motion, but only when the drawn
            // point really is at least half that far from where the high water
            // was drawn (see ProjectedBackwardCheck).
            // Where the shape folds back over itself (a loop, a terminal) the
            // projection can jump by tens of metres while the dot moved
            // centimetres: not a move. A projection outside the search window
            // is another pass over the same road (vehicle 755: 6198 -> 4538 m
            // for a dot that did not move), so it restarts the high water, as
            // do a trip change and an off-shape frame.
            // Two kinds of glide are exempt from this check, found from the
            // fix pair around the render time (the bus's trip tag lags until
            // the halfway point of a pair):
            //  - a trip-change glide (a.tripId != b.tripId): the next trip's
            //    start can lie behind the old trip's end (a terminal
            //    turnaround), which is real motion; never-backward is a
            //    per-trip rule;
            //  - a pass-correction glide (same trip, b more than 150 m behind
            //    a): the renderer deliberately glides between the two snapped
            //    places instead of drawing along the shape;
            //  - a reverse-run stretch (either fix stored without progress by
            //    the store's reverse rule): the bus is driving the shape
            //    backward, so the renderer draws its raw GPS and the
            //    projection on the shape falls with it;
            //  - a spur glide (same trip, b ahead of a along the shape by far
            //    more than their map distance, the renderer's 1.6× / +200 m
            //    rule): the bus skipped a loop or spur, so the renderer glides
            //    across its base, which projects behind the high water at
            //    first.
            // The high water restarts when such a glide ends.
            final renderAt = t.subtract(renderer.currentDelayFor(track.vehicleId) ?? renderer.delayFor(track));
            var exemptGlide = false;
            for (var k = 0; k + 1 < track.fixes.length; k++) {
              final a = track.fixes[k], b = track.fixes[k + 1];
              if (!renderAt.isBefore(a.gpsTime) && renderAt.isBefore(b.gpsTime)) {
                final tripChange = a.tripId != b.tripId;
                final passCorrection = !tripChange && a.progress != null && b.progress != null && b.progress! < a.progress! - 150;
                final reverseRun = a.progressWithheld || b.progressWithheld;
                exemptGlide = tripChange || passCorrection || reverseRun || (!tripChange && _spurStep(a, b));
                break;
              }
            }
            final flagged = backwardCheck.observe(
              vehicleId: bus.vehicleId,
              trip: bus.tripId,
              along: along,
              reseeded: proj.reseeded,
              exempt: exemptGlide,
              lat: bus.lat,
              lon: bus.lon,
              label: '+${t.difference(frames.first.$1).inSeconds}s',
            );
            if (flagged != null) backwardProjected.add(flagged);
            // The frame that sees a data gap (a newest fix over 60 s after the
            // previous one, or a re-created track) snaps by design, so the
            // continuity limit does not apply to it.
            final latestGps = track.fixes.last.gpsTime;
            final prevLatest = lastLatest[bus.vehicleId];
            lastLatest[bus.vehicleId] = latestGps;
            final snapFrame = prevLatest != null &&
                prevLatest != latestGps &&
                (latestGps.difference(prevLatest) > const Duration(seconds: 60) || !track.fixes.any((f) => f.gpsTime == prevLatest));
            if (prev == null) continue;
            final meters = NearestStopService.haversineDistance(prev.lat, prev.lon, bus.lat, bus.lon);
            if (!snapFrame) maxKmh = math.max(maxKmh, meters / 0.12 * 3.6);
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
      expect(backwardProjected, isEmpty, reason: '${backwardProjected.length} drops over 5 m below the high water:\n${backwardProjected.take(5).join('\n')}');
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

/// Whether a → b steps further along the shape than the renderer believes
/// for their map distance (DelayedTrackRenderer's 1.6× / +200 m rule).
bool _spurStep(TrackFix a, TrackFix b) {
  final ap = a.progress, bp = b.progress;
  if (ap == null || bp == null || a.shapeId != b.shapeId || bp - ap <= 200) return false;
  final geo = NearestStopService.haversineDistance(a.snappedLat ?? a.lat, a.snappedLon ?? a.lon, b.snappedLat ?? b.lat, b.snappedLon ?? b.lon);
  return bp - ap > math.max(1.6 * geo, geo + 200);
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

/// The cumulative projected-backward check of the replay: the projection of
/// the drawn point on the trip's shape falling more than 5 m below the
/// vehicle's high water on that trip is backward motion, but only when the
/// dot really is at least half that far from where the high water was drawn.
/// (The drawn distance is a chord and the drop an arc along the route, so on a
/// curve the chord is shorter; a fold in the shape can make the projection
/// jump by tens of metres while the dot moved centimetres, which is not a
/// move.) A reseeded projection, a trip change and an exempt glide restart the
/// high water, as does a frame with no projection.
class ProjectedBackwardCheck {
  final _highWater = <String, ({String? trip, double along, double lat, double lon})>{};

  /// A description when this frame is a backward move, else null.
  String? observe({
    required String vehicleId,
    required String? trip,
    required double? along,
    required bool reseeded,
    required bool exempt,
    required double lat,
    required double lon,
    required String label,
  }) {
    final hw = _highWater[vehicleId];
    if (along == null || exempt) {
      _highWater.remove(vehicleId);
      return null;
    }
    if (reseeded || hw == null || hw.trip != trip || along >= hw.along) {
      _highWater[vehicleId] = (trip: trip, along: along, lat: lat, lon: lon);
      return null;
    }
    final drop = hw.along - along;
    final shown = NearestStopService.haversineDistance(hw.lat, hw.lon, lat, lon);
    if (drop > 5 && shown >= 0.5 * drop) {
      return '$vehicleId $label high water ${hw.along.round()} → ${along.round()} (${drop.round()} m), drawn ${shown.round()} m from the high water';
    }
    return null;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/heading_smoother.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/ui/map/map_layers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/replay_clock.dart';

/// Replays the 22-bus capture at the map's 120 ms frame rate with one bus
/// followed, and checks the spec §3.5 rule that following never switches to a
/// different vehicle: on every frame the emphasised marker and the follow
/// snapshot are about the followed vehicle and no other.
void main() {
  const fixture = 'test/fixtures/timetrack/replay_2026-10-04_22bus';

  test('the followed vehicle never changes over a replay', () async {
    final repo = GtfsRepository();
    await repo.loadFromDirectory('$fixture/gtfs');
    final geometry = RouteGeometry(repo);
    final store = BusTrackStore(geometry);
    final renderer = DelayedTrackRenderer(geometry);
    final json = jsonDecode(File('$fixture/capture.json').readAsStringSync()) as Map<String, dynamic>;
    final rawFrames = (json['frames'] as List).cast<Map<String, dynamic>>();
    final clock = ReplayClock.fromFrames(rawFrames);
    final frames = [
      for (final f in rawFrames)
        if (f['status_code'] == 200)
          (clock.toLocal(DateTime.parse(f['fetch_time'] as String)),
           [for (final v in (f['vehicles'] as List)) TimeTrackVehicle.fromJson(v as Map<String, dynamic>)]),
    ];
    expect(frames.length, greaterThan(20));

    // The vehicle with a track in the most polls (counted on a store of its
    // own, so the ids are the ones the map uses).
    final polls = <String, int>{};
    final counting = BusTrackStore(geometry);
    for (final (poll, vehicles) in frames) {
      counting.ingest(vehicles, poll);
      for (final id in counting.tracks.values.map((t) => t.vehicleId)) {
        polls[id] = (polls[id] ?? 0) + 1;
      }
    }
    final followed = (polls.entries.toList()..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        }))
        .first
        .key;

    FollowTracker newTracker() => FollowTracker(vehicleId: followed, stopsFor: geometry.tripStops);
    var tracker = newTracker();
    final headings = HeadingSmoother();
    const step = Duration(milliseconds: 120);
    var checked = 0;
    var withBus = 0;
    var withMarker = 0;

    for (var i = 0; i < frames.length; i++) {
      final (poll, vehicles) = frames[i];
      store.ingest(vehicles, poll);
      final end = i + 1 < frames.length ? frames[i + 1].$1 : poll.add(const Duration(seconds: 5));
      for (var t = poll; t.isBefore(end); t = t.add(step)) {
        final drawn = renderer.renderAll(store.tracks.values, t);
        final tracking = {
          for (final track in store.tracks.values)
            track.vehicleId: BusTrackingState.fromTrack(track, stale: store.isStale(track, t)),
        };
        final markers = busMarkers(
          tracking: tracking,
          drawn: drawn,
          routeFilter: const {},
          headings: headings,
          now: t,
          followedVehicleId: followed,
        );
        final emphasised = markers.where((m) => m.emphasis == MarkerEmphasis.followed).toList();
        expect(emphasised.length, lessThanOrEqualTo(1), reason: 'one followed marker at +${t.difference(frames.first.$1).inSeconds}s');
        for (final m in emphasised) {
          expect(m.vehicleId, followed);
        }
        if (emphasised.isNotEmpty) withMarker++;

        final snapshot = tracker.update(
          bus: tracking[followed],
          drawnProgress: drawn[followed]?.progress,
          yourStopId: null,
          now: t,
        );
        expect(snapshot.vehicleId, followed);
        expect(snapshot.bus == null || snapshot.bus!.vehicleId == followed, isTrue,
            reason: 'snapshot.bus is ${snapshot.bus?.vehicleId} while following $followed');
        if (snapshot.bus != null) withBus++;
        checked++;
        // A follow that has ended stays ended, so a new follow of the same
        // vehicle starts here, as the rider tapping Follow again would.
        if (snapshot.ended != null) {
          tracker = newTracker();
        }
      }
    }

    // The replay exercised a real follow.
    expect(checked, greaterThan(0));
    expect(withBus, greaterThan(0), reason: 'vehicle $followed was never followed over $checked frames');
    expect(withMarker, greaterThan(0));
  });
}

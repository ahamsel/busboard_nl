import 'dart:convert';
import 'dart:io';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/heading_smoother.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/ui/map/map_layers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/replay_clock.dart';

const _fixture = 'test/fixtures/timetrack/replay_2026-10-04_22bus';
const _step = Duration(milliseconds: 120);

typedef _Frames = List<(DateTime, List<TimeTrackVehicle>)>;

Future<(GtfsRepository, RouteGeometry, _Frames)> _load() async {
  final repo = GtfsRepository();
  await repo.loadFromDirectory('$_fixture/gtfs');
  final json = jsonDecode(File('$_fixture/capture.json').readAsStringSync()) as Map<String, dynamic>;
  final rawFrames = (json['frames'] as List).cast<Map<String, dynamic>>();
  final clock = ReplayClock.fromFrames(rawFrames);
  final frames = [
    for (final f in rawFrames)
      if (f['status_code'] == 200)
        (clock.toLocal(DateTime.parse(f['fetch_time'] as String)),
         [for (final v in (f['vehicles'] as List)) TimeTrackVehicle.fromJson(v as Map<String, dynamic>)]),
  ];
  return (repo, RouteGeometry(repo), frames);
}

/// Runs the map pipeline at its 120 ms frame rate (track store, delayed
/// renderer and a follow tracker wired as the map screen wires them) and
/// calls [onFrame] with every frame's state.
void _replay(
  RouteGeometry geometry,
  _Frames frames,
  void Function(DateTime t, Map<String, BusTrackingState> tracking, Map<String, RenderedBus> drawn) onFrame,
) {
  final store = BusTrackStore(geometry);
  final renderer = DelayedTrackRenderer(geometry);
  for (var i = 0; i < frames.length; i++) {
    final (poll, vehicles) = frames[i];
    store.ingest(vehicles, poll);
    final end = i + 1 < frames.length ? frames[i + 1].$1 : poll.add(const Duration(seconds: 5));
    for (var t = poll; t.isBefore(end); t = t.add(_step)) {
      final drawn = renderer.renderAll(store.tracks.values, t);
      final tracking = {
        for (final track in store.tracks.values)
          track.vehicleId: BusTrackingState.fromTrack(track, stale: store.isStale(track, t)),
      };
      onFrame(t, tracking, drawn);
    }
  }
}

/// How a follow of [vehicleId] to [yourStopId] ends over the replay: the
/// ending, and whether the card had shown "Arrived" by then.
({FollowEnd? ended, bool arrived}) _follow(RouteGeometry geometry, _Frames frames, String vehicleId, String yourStopId) {
  final tracker = FollowTracker(vehicleId: vehicleId, stopsFor: geometry.tripStops, snap: geometry.snap);
  FollowSnapshot? last;
  _replay(geometry, frames, (t, tracking, drawn) {
    if (last?.ended != null) return;
    last = tracker.update(
      bus: tracking[vehicleId],
      drawnProgress: drawn[vehicleId]?.progress,
      drawnTripId: drawn[vehicleId]?.tripId,
      yourStopId: yourStopId,
      now: t,
    );
  });
  return (ended: last?.ended, arrived: last?.arrived ?? false);
}

/// [frames] with [vehicleId] relabelled with [nextTripId] from its first fix
/// within [meters] of [stop] on: the feed's early, clock-driven switch (the
/// diagnosis' v1311 rolled over 340–470 m before its terminal).
_Frames _relabelEarly(_Frames frames, String vehicleId, String nextTripId, StopLike stop, double meters) {
  var switched = false;
  return [
    for (final (t, vehicles) in frames)
      (t, [
        for (final v in vehicles)
          if (v.vehicle != vehicleId)
            v
          else if (switched ||
              (switched = NearestStopService.haversineDistance(v.busLat, v.busLon, stop.lat, stop.lon) < meters))
            TimeTrackVehicle.fromJson({...v.toJson(), 'gtfsTripId': nextTripId})
          else
            v,
      ]),
  ];
}

typedef StopLike = ({double lat, double lon});

void main() {
  // Bus 1418 runs route 10's trip 262400 to Kelsey Drive (last stop 2610)
  // and the feed rolls it over to 262380 about 5 min into the capture.
  const bus = '1418';
  const trip = '262400';
  const nextTrip = '262380';

  test('the followed vehicle never changes over a replay', () async {
    final (_, geometry, frames) = await _load();
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

    final tracker = FollowTracker(vehicleId: followed, stopsFor: geometry.tripStops, snap: geometry.snap);
    final headings = HeadingSmoother();
    var checked = 0;
    var withBus = 0;
    var withMarker = 0;
    var endings = 0;
    FollowEnd? ended;

    _replay(geometry, frames, (t, tracking, drawn) {
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
        drawnTripId: drawn[followed]?.tripId,
        yourStopId: null,
        now: t,
      );
      expect(snapshot.vehicleId, followed);
      expect(snapshot.bus == null || snapshot.bus!.vehicleId == followed, isTrue,
          reason: 'snapshot.bus is ${snapshot.bus?.vehicleId} while following $followed');
      if (snapshot.bus != null) withBus++;
      checked++;
      // An ending is final: it never changes, and never comes back as another.
      if (ended != null) expect(snapshot.ended, ended);
      if (snapshot.ended != null && ended == null) {
        ended = snapshot.ended;
        endings++;
      }
    });

    // The replay exercised a real follow.
    expect(checked, greaterThan(0));
    expect(withBus, greaterThan(0), reason: 'vehicle $followed was never followed over $checked frames');
    expect(withMarker, greaterThan(0));
    expect(endings, lessThanOrEqualTo(1));
  });

  group('a follow to the end of a trip that the feed rolls over', () {
    test('real feed: followed to the last stop or 3 before it, the bus arrives', () async {
      final (_, geometry, frames) = await _load();
      final placed = geometry.tripStops(trip, geometry.shapeIdForTrip(trip)!).where((s) => s.progress != null).toList();
      expect(placed.last.stopId, '2610');
      for (final stop in [placed.last, placed[placed.length - 4]]) {
        final r = _follow(geometry, frames, bus, stop.stopId);
        expect(r.ended, FollowEnd.arrived, reason: 'followed to ${stop.stopId}');
      }
      // Bus 2444 is relabelled at +75 s while still pulling in to its
      // terminal (2190): that too is an arrival.
      expect(_follow(geometry, frames, '2444', '2190').ended, FollowEnd.arrived);
    });

    test('an early switch (v1311-like) still ends as arrived at the last stop and 3 before it', () async {
      final (repo, geometry, frames) = await _load();
      final placed = geometry.tripStops(trip, geometry.shapeIdForTrip(trip)!).where((s) => s.progress != null).toList();
      StopLike at(String id) => (lat: repo.stopsById[id]!.stopLat, lon: repo.stopsById[id]!.stopLon);

      // Relabelled 470 m before the terminal, as v1311 was.
      final terminal = placed.last;
      final early = _relabelEarly(frames, bus, nextTrip, at(terminal.stopId), 470);
      var r = _follow(geometry, early, bus, terminal.stopId);
      expect((r.ended, r.arrived), (FollowEnd.arrived, true), reason: 'followed to the terminal ${terminal.stopId}');

      // Relabelled 340 m before a stop 3 before the terminal.
      final threeBefore = placed[placed.length - 4];
      final earlier = _relabelEarly(frames, bus, nextTrip, at(threeBefore.stopId), 340);
      r = _follow(geometry, earlier, bus, threeBefore.stopId);
      expect((r.ended, r.arrived), (FollowEnd.arrived, true), reason: 'followed to ${threeBefore.stopId}');
    });
  });
}

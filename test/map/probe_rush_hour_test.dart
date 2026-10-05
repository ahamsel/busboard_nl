// Diagnostic probe (not a regression test): replays the 2026-10-05 rush-hour
// capture through the Phase 3b pipeline (RouteGeometry -> BusTrackStore ->
// DelayedTrackRenderer) at 120 ms frames on a fake clock and measures every
// drawn dot against its own vehicle's GPS track, with the metrics of
// DIAGNOSIS_2026-10-05.md (far episodes, trip-switch jumps, lurches, named
// cases). Skipped unless PROBE_CAPTURE and PROBE_GTFS are set.
//
//   PROBE_CAPTURE=test/fixtures/timetrack/capture_2026-10-05.json \
//   PROBE_GTFS=build/gtfs_2026-09-01 PROBE_OUT=build/probe_rush_hour.txt \
//   flutter test test/map/probe_rush_hour_test.dart
//
// "Starved" keeps the 3b-1 definition (render time more than 5 s past the
// newest fix) so runs stay comparable as the renderer's rules change.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_track.dart';
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/replay_clock.dart';

double hav(double a, double b, double c, double d) => NearestStopService.haversineDistance(a, b, c, d);

class G {
  G(this.t, this.lat, this.lon, this.trip, this.route);
  final DateTime t;
  final double lat, lon;
  final String trip;
  final int route;
}

class Episode {
  Episode(this.start, this.trip, this.lat, this.lon);
  final DateTime start;
  final String? trip;
  final double lat, lon;
  double max = 0;
  DateTime? maxAt;
}

class SwitchEv {
  SwitchEv(this.vid, this.a, this.b, this.fetch, this.recreated);
  final String vid;
  final TrackFix a, b;
  final DateTime fetch;
  final bool recreated;
  bool started = false, done = false;
  double? sLat, sLon, eLat, eLon;
  double jump15 = 0, maxDRender = 0, maxDLatest = 0;
  int frames = 0;
}

class VS {
  final hist = <(DateTime, double, double)>[]; // wall time, lat, lon (last 13 frames)
  final ep = <String, Episode?>{'render': null, 'latest': null, 'old': null};
  String? prevTrip;
  double? prevP;
  double? prevLat, prevLon;
  DateTime? lastSample;
  double? sampleLat, sampleLon;
  DateTime? sampleRenderAt;
  int frozenRun = 0; // seconds
  DateTime? lastLurch;
  DateTime? lastWrongWay;
  final w5 = <(DateTime, double, double, DateTime)>[]; // 1 s samples: wall, lat, lon, renderAt
}

void main() {
  final capturePath = Platform.environment['PROBE_CAPTURE'];
  final gtfsDir = Platform.environment['PROBE_GTFS'];
  test('rush-hour probe of the 3b pipeline', () async {
    final outPath = Platform.environment['PROBE_OUT'] ?? 'build/probe_rush_hour.txt';
    final repo = GtfsRepository();
    await repo.loadFromDirectory(gtfsDir!);
    final geometry = RouteGeometry(repo);
    final store = BusTrackStore(geometry);
    final renderer = DelayedTrackRenderer(geometry);
    final json = jsonDecode(File(capturePath!).readAsStringSync()) as Map<String, dynamic>;
    final rawFrames = (json['frames'] as List).cast<Map<String, dynamic>>();
    final clock = ReplayClock.fromFrames(rawFrames);
    final offset = clock.offset;
    String z(DateTime local) {
      final u = local.subtract(offset);
      String two(int x) => x.toString().padLeft(2, '0');
      return '${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
    }

    DateTime fromZ(String hms) {
      final p = hms.split(':').map(int.parse).toList();
      return clock.toLocal(DateTime.utc(2026, 10, 5, p[0], p[1], p.length > 2 ? p[2] : 0));
    }

    DateTime gpsTimeOf(int secs, DateTime fetch) {
      if (secs <= 0 || secs >= Duration.secondsPerDay) return fetch;
      DateTime onDay(int d) => DateTime(fetch.year, fetch.month, fetch.day + d, 0, 0, secs);
      var t = onDay(0);
      final diff = fetch.difference(t).inSeconds;
      if (diff > 43200) t = onDay(1);
      if (diff < -43200) t = onDay(-1);
      return t;
    }

    final frames = <(DateTime, List<TimeTrackVehicle>)>[
      for (final f in rawFrames)
        if (f['status_code'] == 200)
          (clock.toLocal(DateTime.parse(f['fetch_time'] as String)),
           [for (final v in (f['vehicles'] as List)) TimeTrackVehicle.fromJson(v as Map<String, dynamic>)]),
    ];

    // ── Truth: each vehicle's own GPS track, by GPS time (advancing only).
    final truth = <String, List<G>>{};
    // Old-probe truth: distinct positions stamped by the fetch time first seen.
    final oldTruth = <String, List<G>>{};
    final ghostFrames = <String, int>{};
    for (final (fetch, vlist) in frames) {
      for (final v in vlist) {
        if (v.busLat == 0 || v.busLon == 0) continue;
        final g = gpsTimeOf(v.positionTimeSeconds, fetch);
        final tr = truth.putIfAbsent(v.vehicle, () => []);
        if (tr.isEmpty || g.isAfter(tr.last.t)) tr.add(G(g, v.busLat, v.busLon, v.gtfsTripId, v.routeNumber));
        final ot = oldTruth.putIfAbsent(v.vehicle, () => []);
        if (ot.isEmpty || ot.last.lat != v.busLat || ot.last.lon != v.busLon) ot.add(G(fetch, v.busLat, v.busLon, v.gtfsTripId, v.routeNumber));
        if (fetch.difference(g) > const Duration(minutes: 5)) ghostFrames[v.vehicle] = (ghostFrames[v.vehicle] ?? 0) + 1;
      }
    }
    (double, double) interp(List<G> tr, DateTime t) {
      if (!t.isAfter(tr.first.t)) return (tr.first.lat, tr.first.lon);
      if (!t.isBefore(tr.last.t)) return (tr.last.lat, tr.last.lon);
      var lo = 0, hi = tr.length - 1;
      while (hi - lo > 1) {
        final m = (lo + hi) >> 1;
        if (tr[m].t.isAfter(t)) {
          hi = m;
        } else {
          lo = m;
        }
      }
      final span = tr[hi].t.difference(tr[lo].t).inMicroseconds;
      final u = span <= 0 ? 1.0 : t.difference(tr[lo].t).inMicroseconds / span;
      return (tr[lo].lat + (tr[hi].lat - tr[lo].lat) * u, tr[lo].lon + (tr[hi].lon - tr[lo].lon) * u);
    }

    // ── Board identity: who buildTripIndex links each duplicated trip to.
    final boardDup = <String, Map<String, int>>{}; // trip -> winner vehicle -> polls
    var dupPolls = 0;
    for (final (_, vlist) in frames) {
      final byTrip = <String, List<String>>{};
      for (final v in vlist) {
        if (v.gtfsTripId.isNotEmpty) byTrip.putIfAbsent(v.gtfsTripId, () => []).add(v.vehicle);
      }
      final index = TimeTrackApi.buildTripIndex(vlist);
      var any = false;
      for (final e in byTrip.entries) {
        if (e.value.length < 2) continue;
        any = true;
        final w = index[e.key]!.vehicle;
        final key = '${e.key} [${e.value.join("/")}]';
        boardDup.putIfAbsent(key, () => {})[w] = (boardDup[key]![w] ?? 0) + 1;
      }
      if (any) dupPolls++;
    }

    // ── Trace windows for the named cases.
    final traceSpecs = <(String, DateTime, DateTime, String)>[];
    void tw(String vid, String from, String to, String label) => traceSpecs.add((vid, fromZ(from), fromZ(to), label));
    tw('1629', '12:04:00', '12:38:00', 'ghost 1629 (same trip as 1311)');
    tw('1311', '12:04:00', '12:38:00', 'real 1311 during the ghost');
    tw('1628', '12:24:30', '12:40:00', 'v1628 trip change 12:25:33 (old progress leak)');
    tw('1628', '13:30:30', '13:59:30', 'v1628 trip change 13:31:44 (old progress leak)');
    tw('2568', '12:50:00', '13:25:00', 'v2568 deadhead under finished trip (late switch)');
    tw('2442', '12:14:00', '12:33:00', 'v2442 late switch 12:28:43');
    tw('1312', '12:17:00', '12:26:00', 'v1312 late switch 12:22:23');
    tw('1312', '13:21:00', '13:30:00', 'v1312 late switch 13:26:54');
    tw('1311', '12:10:30', '12:16:00', 'v1311 early switch 12:12:13');
    tw('1311', '13:15:30', '13:21:00', 'v1311 early switch 13:17:14');
    tw('860', '13:12:30', '13:19:00', 'v860 early switch 13:14:14');
    tw('1207', '12:22:00', '12:27:00', 'v1207 early switch 12:23:43');
    tw('2574', '13:35:00', '13:50:00', 'v2574 runaway 13:39');
    tw('1416', '12:04:30', '12:13:00', 'route 2 double-back v1416 12:07');
    tw('1630', '12:41:00', '12:50:00', 'route 2 double-back v1630 12:44');
    tw('1310', '12:44:00', '12:53:00', 'route 2 double-back v1310 12:47');
    tw('1310', '13:43:00', '13:52:00', 'route 2 double-back v1310 13:46');
    tw('2570', '13:08:00', '13:17:00', 'route 2 double-back v2570 13:11');
    tw('2439', '12:07:30', '12:10:30', 'v2439 far episode 12:08');
    tw('2439', '13:12:30', '13:15:00', 'v2439 far episode 13:13');
    tw('2446', '12:41:30', '12:44:00', 'v2446 far episode 12:42');
    tw('1627', '12:50:30', '12:52:30', 'v1627 snap 12:51:45 after data gap');
    tw('2446', '12:56:30', '12:58:30', 'v2446 snap 12:58:06 after data gap');
    tw('1311', '12:04:25', '12:06:00', 'v1311 snap 12:05:25');
    tw('858', '13:03:30', '13:12:30', 'v858 reverse-rule run 13:04');
    final traceStats = <int, Map<String, num>>{};
    final traceOut = <int, StringBuffer>{};

    const hotLat = 47.5869, hotLon = -52.6915;
    final hot = <String, num>{'frames': 0, 'maxDRender': 0, 'over300': 0, 'frozenSec': 0, 'wrongWay': 0};

    final out = StringBuffer();
    final vs = <String, VS>{};
    final switches = <SwitchEv>[];
    final pending = <String, List<SwitchEv>>{};
    final closed = <String, List<(String vid, DateTime start, DateTime end, double max, String? trip, bool active, DateTime? maxAt)>>{
      'render': [], 'latest': [], 'old': [],
    };
    final dR = <double>[], dL = <double>[], dO = <double>[];
    final drawnCount = <String, int>{};
    final snaps = <(double, String)>[];
    var snapsOver100 = 0;
    var maxStepNonSnap = 0.0;
    final lurch = <String, int>{'FWDLURCH': 0, 'BACKJUMP': 0, 'SIDEJUMP': 0, 'AMBIGJUMP': 0};
    final lurchLines = <String>[];
    var progBackward = 0;
    var progBackwardMax = 0.0;
    final progBackLines = <String>[];
    var wrongWay = 0;
    final wrongWayLines = <String>[];
    var frozenSec = 0, frozenStarved = 0, movingSec = 0;
    final frozenRuns = <(String, DateTime, int)>[]; // vid, end, seconds (runs >= 10 s)
    var starvedFrames = 0, totalFrames = 0, delayAtMax = 0, fastFrames = 0;
    const starvedAfter = Duration(seconds: 5);
    final delays = <double>[];
    // Snap frames over 100 m on a track re-created this frame (a route
    // change): those snap by design.
    var snapsOver100Recreated = 0;
    final seenLatest = <String, DateTime>{};
    // Fixes the store withheld progress from (the reverse rule).
    var newFixes = 0, withheldFixes = 0;
    final withheldSince = <String, DateTime>{};
    final withheldRuns = <String, (DateTime, int)>{};
    final withheldLog = <String, Map<String, int>>{};

    void closeEp(String kind, String vid, VS s, DateTime now, {bool active = false}) {
      final e = s.ep[kind];
      if (e == null) return;
      s.ep[kind] = null;
      if (now.difference(e.start).inSeconds >= 60 || active) {
        closed[kind]!.add((vid, e.start, now, e.max, e.trip, active, e.maxAt));
      }
    }

    void finishSwitch(SwitchEv sw) {
      sw.done = true;
    }

    const step = Duration(milliseconds: 120);
    for (var i = 0; i < frames.length; i++) {
      final (poll, vehicles) = frames[i];
      final before = {for (final t in store.tracks.values) t.vehicleId: t.latest};
      store.ingest(vehicles, poll);
      for (final t in store.tracks.values) {
        final latest = t.latest;
        if (identical(before[t.vehicleId], latest)) continue;
        newFixes++;
        final withheld = latest.progress == null && latest.snapProgress != null;
        if (withheld) {
          withheldFixes++;
          final start = withheldSince.putIfAbsent(t.vehicleId, () => latest.gpsTime);
          final secs = latest.gpsTime.difference(start).inSeconds;
          final run = withheldRuns[t.vehicleId];
          if (run == null || run.$1 != start) {
            withheldRuns[t.vehicleId] = (start, secs);
          } else {
            withheldRuns[t.vehicleId] = (start, secs);
          }
          if (secs >= 0) {
            withheldLog[t.vehicleId] = {...?withheldLog[t.vehicleId], z(start): secs};
          }
        } else {
          withheldSince.remove(t.vehicleId);
        }
      }
      for (final t in store.tracks.values) {
        final b0 = before[t.vehicleId];
        final latest = t.latest;
        if (b0 == null || identical(b0, latest)) continue;
        final recreated = !t.fixes.any((f) => identical(f, b0));
        if (b0.tripId != latest.tripId || recreated) {
          final sw = SwitchEv(t.vehicleId, b0, latest, poll, recreated);
          switches.add(sw);
          pending.putIfAbsent(t.vehicleId, () => []).add(sw);
        }
      }
      // Dropped tracks close their episodes and switches.
      for (final vid in vs.keys.toList()) {
        if (!store.tracks.containsKey(vid)) {
          for (final k in ['render', 'latest', 'old']) {
            closeEp(k, vid, vs[vid]!, poll);
          }
          vs.remove(vid);
          for (final sw in pending.remove(vid) ?? const <SwitchEv>[]) {
            finishSwitch(sw);
          }
        }
      }
      final end = i + 1 < frames.length ? frames[i + 1].$1 : poll.add(const Duration(seconds: 5));
      for (var t = poll; t.isBefore(end); t = t.add(step)) {
        final drawn = renderer.renderAll(store.tracks.values, t);
        for (final track in store.tracks.values) {
          final vid = track.vehicleId;
          final bus = drawn[vid]!;
          totalFrames++;
          drawnCount[vid] = (drawnCount[vid] ?? 0) + 1;
          final s = vs.putIfAbsent(vid, VS.new);
          final delay = renderer.currentDelayFor(vid) ?? renderer.delayFor(track);
          final renderAt = t.subtract(delay);
          final starved = renderAt.isAfter(track.latest.gpsTime.add(starvedAfter));
          if (starved) starvedFrames++;
          if (delay >= DelayedTrackRenderer.maxDelay - const Duration(milliseconds: 100)) delayAtMax++;
          delays.add(delay.inMilliseconds / 1000.0);
          final prevSeen = seenLatest[vid];
          final recreatedNow = prevSeen != null && prevSeen != track.latest.gpsTime && !track.fixes.any((f) => f.gpsTime == prevSeen);
          seenLatest[vid] = track.latest.gpsTime;
          final tr = truth[vid]!;
          final g = interp(tr, renderAt);
          final dRender = hav(bus.lat, bus.lon, g.$1, g.$2);
          final latest = track.latest;
          final dLatest = hav(bus.lat, bus.lon, latest.lat, latest.lon);
          final og = interp(oldTruth[vid]!, t);
          final dOld = hav(bus.lat, bus.lon, og.$1, og.$2);
          dR.add(dRender);
          dL.add(dLatest);
          dO.add(dOld);
          for (final (kind, d) in [('render', dRender), ('latest', dLatest), ('old', dOld)]) {
            final e = s.ep[kind];
            if (d > 300) {
              final ne = e ?? (s.ep[kind] = Episode(t, bus.tripId, bus.lat, bus.lon));
              if (d > ne.max) {
                ne.max = d;
                ne.maxAt = t;
              }
            } else if (e != null) {
              closeEp(kind, vid, s, t);
            }
          }

          // Per-frame step and snaps.
          if (s.prevLat != null) {
            final stepM = hav(s.prevLat!, s.prevLon!, bus.lat, bus.lon);
            if (stepM > 30 * 0.12 * 1.05 + 0.5) {
              snaps.add((stepM, '${z(t)} v$vid step=${stepM.round()}m trip=${bus.tripId}${recreatedNow ? ' RECREATED' : ''}'));
              if (stepM > 100) {
                snapsOver100++;
                if (recreatedNow) snapsOver100Recreated++;
              }
            } else {
              maxStepNonSnap = math.max(maxStepNonSnap, stepM);
              if (stepM > 2.5) fastFrames++;
            }
          }
          // Progress-based backward (same trip).
          if (s.prevTrip == bus.tripId && s.prevP != null && bus.progress != null && bus.progress! < s.prevP! - 0.01) {
            progBackward++;
            final drop = s.prevP! - bus.progress!;
            progBackwardMax = math.max(progBackwardMax, drop);
            if (progBackLines.length < 20) progBackLines.add('${z(t)} v$vid ${s.prevP!.round()}->${bus.progress!.round()}');
          }

          // Lurches (old definition: >150 m over 11 frames = 1.2 s, 4 s cooldown).
          s.hist.add((t, bus.lat, bus.lon));
          if (s.hist.length > 13) s.hist.removeAt(0);
          if (s.hist.length >= 11) {
            final h0 = s.hist[s.hist.length - 11];
            final geo = hav(h0.$2, h0.$3, bus.lat, bus.lon);
            if (geo > 150 && (s.lastLurch == null || t.difference(s.lastLurch!).inSeconds > 4)) {
              s.lastLurch = t;
              final g0 = interp(tr, renderAt.subtract(const Duration(seconds: 30)));
              final g1 = interp(tr, renderAt.add(const Duration(seconds: 30)));
              final kx = 111320.0 * math.cos(bus.lat * math.pi / 180);
              const ky = 110540.0;
              final bx = (g1.$2 - g0.$2) * kx, by = (g1.$1 - g0.$1) * ky;
              final dx = (bus.lon - h0.$3) * kx, dy = (bus.lat - h0.$2) * ky;
              final bl = math.sqrt(bx * bx + by * by);
              final cosv = bl < 50 ? 0.0 : (bx * dx + by * dy) / (bl * geo);
              final kind = bl < 50 ? 'AMBIGJUMP' : cosv < -0.5 ? 'BACKJUMP' : cosv > 0.5 ? 'FWDLURCH' : 'SIDEJUMP';
              lurch[kind] = lurch[kind]! + 1;
              lurchLines.add('${z(t)} v$vid $kind geo=${geo.round()}m cos=${cosv.toStringAsFixed(2)}');
            }
          }

          // 1 s samples: frozen-while-moving and wrong-way creep.
          if (s.lastSample == null || t.difference(s.lastSample!) >= const Duration(seconds: 1)) {
            if (s.lastSample != null && s.sampleRenderAt != null) {
              final dotMove = hav(s.sampleLat!, s.sampleLon!, bus.lat, bus.lon);
              final gPrev = interp(tr, s.sampleRenderAt!);
              final busMove = hav(gPrev.$1, gPrev.$2, g.$1, g.$2);
              final nearHot = hav(g.$1, g.$2, hotLat, hotLon) < 800 && track.routeNumber == 2;
              if (busMove > 4) {
                movingSec++;
                if (dotMove < 1) {
                  frozenSec++;
                  if (starved) frozenStarved++;
                  s.frozenRun++;
                  if (nearHot) hot['frozenSec'] = hot['frozenSec']! + 1;
                } else {
                  if (s.frozenRun >= 10) frozenRuns.add((vid, t, s.frozenRun));
                  s.frozenRun = 0;
                }
              } else {
                if (s.frozenRun >= 10) frozenRuns.add((vid, t, s.frozenRun));
                s.frozenRun = 0;
              }
            }
            s.w5.add((t, bus.lat, bus.lon, renderAt));
            if (s.w5.length > 6) s.w5.removeAt(0);
            if (s.w5.length == 6) {
              final w0 = s.w5.first;
              final dot = hav(w0.$2, w0.$3, bus.lat, bus.lon);
              final ga = interp(tr, w0.$4);
              final busM = hav(ga.$1, ga.$2, g.$1, g.$2);
              if (dot > 25 && busM > 25 && (s.lastWrongWay == null || t.difference(s.lastWrongWay!).inSeconds > 10)) {
                final kx = 111320.0 * math.cos(bus.lat * math.pi / 180);
                const ky = 110540.0;
                final bx = (g.$2 - ga.$2) * kx, by = (g.$1 - ga.$1) * ky;
                final dx = (bus.lon - w0.$3) * kx, dy = (bus.lat - w0.$2) * ky;
                final cosv = (bx * dx + by * dy) / (math.sqrt(bx * bx + by * by) * math.sqrt(dx * dx + dy * dy));
                if (cosv < -0.5) {
                  s.lastWrongWay = t;
                  wrongWay++;
                  if (hav(g.$1, g.$2, hotLat, hotLon) < 800 && track.routeNumber == 2) hot['wrongWay'] = hot['wrongWay']! + 1;
                  wrongWayLines.add('${z(t)} v$vid dot=${dot.round()}m bus=${busM.round()}m cos=${cosv.toStringAsFixed(2)} dRender=${dRender.round()} trip=${bus.tripId}');
                }
              }
            }
            s.lastSample = t;
            s.sampleLat = bus.lat;
            s.sampleLon = bus.lon;
            s.sampleRenderAt = renderAt;
          }

          // Route 2 hotspot.
          if (track.routeNumber == 2 && hav(g.$1, g.$2, hotLat, hotLon) < 800) {
            hot['frames'] = hot['frames']! + 1;
            hot['maxDRender'] = math.max(hot['maxDRender']!.toDouble(), dRender);
            if (dRender > 300) hot['over300'] = hot['over300']! + 1;
          }

          // Trip-switch windows.
          for (final sw in pending[vid] ?? const <SwitchEv>[]) {
            if (sw.done) continue;
            if (!sw.started && !renderAt.isBefore(sw.a.gpsTime)) {
              sw.started = true;
              sw.sLat = bus.lat;
              sw.sLon = bus.lon;
            }
            if (!sw.started) continue;
            sw.frames++;
            if (s.hist.length >= 13) {
              final h = s.hist.first; // 12 frames = 1.44 s back
              sw.jump15 = math.max(sw.jump15, hav(h.$2, h.$3, bus.lat, bus.lon));
            }
            sw.maxDRender = math.max(sw.maxDRender, dRender);
            sw.maxDLatest = math.max(sw.maxDLatest, dLatest);
            sw.eLat = bus.lat;
            sw.eLon = bus.lon;
            if (!renderAt.isBefore(sw.b.gpsTime.add(const Duration(seconds: 10)))) finishSwitch(sw);
          }
          pending[vid]?.removeWhere((sw) => sw.done);

          // Trace windows.
          for (var k = 0; k < traceSpecs.length; k++) {
            final (tv, from, to, _) = traceSpecs[k];
            if (tv != vid || t.isBefore(from) || t.isAfter(to)) continue;
            final st = traceStats.putIfAbsent(k, () => {'frames': 0, 'maxDRender': 0, 'maxDLatest': 0, 'over300': 0, 'over150': 0});
            st['frames'] = st['frames']! + 1;
            if (dRender > st['maxDRender']!) {
              st['maxDRender'] = dRender;
              st['maxAt'] = t.millisecondsSinceEpoch;
            }
            st['maxDLatest'] = math.max(st['maxDLatest']!.toDouble(), dLatest);
            if (dRender > 300) st['over300'] = st['over300']! + 1;
            if (dRender > 150) st['over150'] = st['over150']! + 1;
            final buf = traceOut.putIfAbsent(k, StringBuffer.new);
            if (t.millisecond < 120 && t.second % 5 == 0) {
              buf.writeln('  ${z(t)} at=${z(renderAt)} D=${delay.inMilliseconds / 1000}s trip=${bus.tripId} p=${bus.progress?.round()} '
                  'dot=(${bus.lat.toStringAsFixed(5)},${bus.lon.toStringAsFixed(5)}) gps@at=(${g.$1.toStringAsFixed(5)},${g.$2.toStringAsFixed(5)}) '
                  'dRender=${dRender.round()} dLatest=${dLatest.round()} latest[trip=${latest.tripId} p=${latest.progress?.round()} off=${latest.offRoute} gps=${z(latest.gpsTime)}]'
                  '${starved ? " STARVED" : ""}${store.isStale(track, t) ? " STALE" : ""}');
            }
          }

          s.prevTrip = bus.tripId;
          s.prevP = bus.progress;
          s.prevLat = bus.lat;
          s.prevLon = bus.lon;
        }
      }
    }
    final endT = frames.last.$1.add(const Duration(seconds: 5));
    for (final e in vs.entries) {
      for (final k in ['render', 'latest', 'old']) {
        closeEp(k, e.key, e.value, endT, active: e.value.ep[k] != null && endT.difference(e.value.ep[k]!.start).inSeconds >= 60);
      }
    }

    // ── Report.
    double pct(List<double> xs, double q) {
      final s = [...xs]..sort();
      return s[(q * (s.length - 1)).round()];
    }

    out.writeln('# 3b pipeline probe, capture 2026-10-05 ${z(frames.first.$1)}Z..${z(frames.last.$1)}Z, ${frames.length} polls, $totalFrames vehicle-frames');
    out.writeln('offset ${offset.inMinutes} min; vehicles in feed ${truth.length}; drawn ${drawnCount.length}');
    out.writeln('feed entries with GPS older than 5 min at fetch (store drops them): $ghostFrames');
    out.writeln('never drawn: ${truth.keys.where((v) => !drawnCount.containsKey(v)).toList()}');
    out.writeln('\n## Distance dot -> GPS');
    for (final (n, xs) in [('render-time GPS', dR), ('latest fix', dL), ('old-probe GPS@now (fetch-stamped)', dO)]) {
      out.writeln('$n: p50 ${pct(xs, .5).round()} p90 ${pct(xs, .9).round()} p99 ${pct(xs, .99).round()} max ${pct(xs, 1).round()} m; '
          '>300 m ${(100 * xs.where((d) => d > 300).length / xs.length).toStringAsFixed(2)}% of frames');
    }
    out.writeln('\n## Far episodes (>300 m for >=60 s)');
    for (final kind in ['render', 'latest', 'old']) {
      final list = closed[kind]!..sort((a, b) => b.$4.compareTo(a.$4));
      out.writeln('[$kind] count=${list.length} activeAtEnd=${list.where((e) => e.$6).length}');
      for (final e in list.take(40)) {
        out.writeln('  v${e.$1} ${z(e.$2)}..${z(e.$3)} (${e.$3.difference(e.$2).inSeconds}s) max=${e.$4.round()}m at ${e.$7 == null ? "-" : z(e.$7!)} trip=${e.$5}${e.$6 ? " ACTIVE AT END" : ""}');
      }
    }
    out.writeln('\n## Trip switches (${switches.length}; recreated tracks ${switches.where((s) => s.recreated).length})');
    final jumps = [for (final s in switches) s.jump15];
    out.writeln('dot moved >100 m within 1.5 s: ${jumps.where((j) => j > 100).length}; >300 m: ${jumps.where((j) => j > 300).length}; largest ${jumps.isEmpty ? 0 : jumps.reduce(math.max).round()} m');
    final glides = [for (final s in switches) if (s.sLat != null && s.eLat != null) hav(s.sLat!, s.sLon!, s.eLat!, s.eLon!)];
    out.writeln('switch window glide (dot start->end) >100 m: ${glides.where((j) => j > 100).length}; >300 m: ${glides.where((j) => j > 300).length}');
    final mdr = [for (final s in switches) s.maxDRender];
    out.writeln('max dot->render-GPS during switch window >100 m: ${mdr.where((j) => j > 100).length}; >300 m: ${mdr.where((j) => j > 300).length}; largest ${mdr.isEmpty ? 0 : mdr.reduce(math.max).round()} m');
    final sorted = [...switches]..sort((a, b) => b.maxDRender.compareTo(a.maxDRender));
    for (final s in sorted.take(30)) {
      out.writeln('  v${s.vid} ${z(s.fetch)} ${s.a.tripId}->${s.b.tripId}${s.recreated ? " RECREATED" : ""} gpsMove=${hav(s.a.lat, s.a.lon, s.b.lat, s.b.lon).round()}m '
          'snapA=${s.a.progress?.round()}${s.a.offRoute ? "(off)" : ""} snapB=${s.b.progress?.round()}${s.b.offRoute ? "(off)" : ""} '
          'glide=${s.sLat == null || s.eLat == null ? "-" : hav(s.sLat!, s.sLon!, s.eLat!, s.eLon!).round()}m jump1.5s=${s.jump15.round()}m maxDRender=${s.maxDRender.round()}m maxDLatest=${s.maxDLatest.round()}m frames=${s.frames}');
    }
    out.writeln('\n## Lurches and backward motion');
    out.writeln('old-definition >150 m in 1.2 s: $lurch');
    for (final l in lurchLines.take(30)) {
      out.writeln('  $l');
    }
    out.writeln('snap frames (step > 30 m/s): ${snaps.length}, of which >100 m: $snapsOver100 ($snapsOver100Recreated on re-created tracks); max non-snap step ${maxStepNonSnap.toStringAsFixed(1)} m/frame');
    final bigSnaps = snaps.where((x) => x.$1 > 20).toList()..sort((a, b) => b.$1.compareTo(a.$1));
    out.writeln('  steps over 20 m: ${bigSnaps.length} (largest 40 below)');
    for (final l in bigSnaps.take(40)) {
      out.writeln('  ${l.$2}');
    }
    out.writeln('progress backward on same trip: $progBackward frames, max drop ${progBackwardMax.toStringAsFixed(1)} m');
    for (final l in progBackLines) {
      out.writeln('  $l');
    }
    out.writeln('wrong-way creep (5 s: dot >25 m opposite to bus >25 m, cos<-0.5): $wrongWay');
    for (final l in wrongWayLines.take(40)) {
      out.writeln('  $l');
    }
    out.writeln('frozen while bus moves: $frozenSec of $movingSec moving vehicle-seconds (${(100 * frozenSec / movingSec).toStringAsFixed(1)}%), '
        'of which starved (render time > newest fix + 5 s) $frozenStarved');
    out.writeln('starved frames: $starvedFrames of $totalFrames (${(100 * starvedFrames / totalFrames).toStringAsFixed(2)}%)');
    out.writeln('reverse rule: $withheldFixes of $newFixes new fixes withheld progress; runs (start: GPS seconds to last withheld fix):');
    for (final e in withheldLog.entries) {
      out.writeln('  v${e.key} ${e.value}');
    }
    out.writeln('drawn delay: p50 ${pct(delays, .5).toStringAsFixed(1)} s, p90 ${pct(delays, .9).toStringAsFixed(1)} s');
    out.writeln('render delay at the ${DelayedTrackRenderer.maxDelay.inSeconds} s cap: $delayAtMax of $totalFrames frames (${(100 * delayAtMax / totalFrames).toStringAsFixed(1)}%); frames drawn faster than 75 km/h (catch-up): $fastFrames');
    frozenRuns.sort((a, b) => b.$3.compareTo(a.$3));
    out.writeln('frozen runs >=10 s: ${frozenRuns.length}; >=30 s: ${frozenRuns.where((r) => r.$3 >= 30).length}');
    for (final r in frozenRuns.take(25)) {
      out.writeln('  v${r.$1} ending ${z(r.$2)} ${r.$3}s');
    }
    out.writeln('\n## Route 2 hotspot (47.5869,-52.6915, 800 m): $hot');
    out.writeln('\n## Board: buildTripIndex on trips reported by two vehicles ($dupPolls polls)');
    for (final e in boardDup.entries) {
      out.writeln('  ${e.key}: winner ${e.value}');
    }
    out.writeln('\n## Named cases');
    for (var k = 0; k < traceSpecs.length; k++) {
      final (vid, from, to, label) = traceSpecs[k];
      final st = traceStats[k];
      out.writeln('\n### $label  (v$vid ${z(from)}..${z(to)})');
      if (st == null) {
        out.writeln('  NOT DRAWN in this window');
        continue;
      }
      out.writeln('  frames ${st['frames']} (${(st['frames']! * 0.12).round()} s drawn); maxDRender ${st['maxDRender']!.round()} m at '
          '${st['maxAt'] == null ? '-' : z(DateTime.fromMillisecondsSinceEpoch(st['maxAt']!.toInt()))}; maxDLatest ${st['maxDLatest']!.round()} m; '
          '>300 m ${(st['over300']! * 0.12).round()} s; >150 m ${(st['over150']! * 0.12).round()} s');
      final sws = switches.where((s) => s.vid == vid && !s.fetch.isBefore(from) && !s.fetch.isAfter(to));
      for (final s in sws) {
        out.writeln('  switch ${z(s.fetch)} ${s.a.tripId}->${s.b.tripId} gpsMove=${hav(s.a.lat, s.a.lon, s.b.lat, s.b.lon).round()}m snapA=${s.a.progress?.round()}${s.a.offRoute ? "(off)" : ""} '
            'snapB=${s.b.progress?.round()}${s.b.offRoute ? "(off)" : ""} jump1.5s=${s.jump15.round()}m maxDRender=${s.maxDRender.round()}m');
      }
      out.write(traceOut[k]?.toString() ?? '');
    }
    File(outPath).writeAsStringSync(out.toString());
    // ignore: avoid_print
    print(out.toString().split('\n## Named cases').first);
  }, skip: capturePath == null || gtfsDir == null ? 'set PROBE_CAPTURE and PROBE_GTFS' : false, timeout: const Timeout(Duration(minutes: 30)));
}

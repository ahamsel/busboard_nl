import 'dart:collection';
import 'dart:math' as math;

import '../../data/realtime/timetrack_models.dart';
import 'bus_track.dart';
import 'route_geometry.dart';
import 'shape_matcher.dart';

/// Keeps one [BusTrack] per physical vehicle from successive feed polls.
///
/// Identity and reset rules (spec §3.4): a route-number change starts a new
/// track; a trip change continues the same track; duplicate or out-of-order
/// GPS times are ignored. Each fix is snapped near where the bus should be
/// (previous progress + speed × time), or for a new bus or trip near the
/// stop it is approaching or its timetable position.
///
/// Reverse rule: a bus whose fixes keep falling along its trip's shape is
/// driving it backward (the feed still labels the finished trip after the bus
/// turned round), so its progress means nothing. Once [reverseRunFixes]
/// fixes in a row on one trip and shape each lie more than
/// [_reverseFallMeters] behind the one before, all of them but the first,
/// and the fixes after them, are stored without progress (and without a
/// snapped place), so the renderer draws the raw GPS, until a fix advances
/// more than [_reverseFallMeters] again or the trip or shape changes. The
/// snap itself is kept in [TrackFix.snapProgress] for the next fix's window.
class BusTrackStore {
  BusTrackStore(this._geometry, {this.maxFixes = 24});

  final RouteGeometry _geometry;
  final int maxFixes;
  final Map<String, BusTrack> _tracks = {};
  int _duplicateAssignments = 0;

  static const Duration staleAfter = Duration(seconds: 90);
  static const Duration dropAfter = Duration(minutes: 5);

  /// How far behind its last progress a fix may snap, and the fixed lead and
  /// speed allowance ahead of it.
  static const double _windowBackMeters = 250;
  static const double _windowAheadMeters = 400;
  static const double _windowMaxSpeedMps = 30;

  /// How many fixes in a row, each behind the one before, make the bus count
  /// as running its shape backward: a single step back is a wrong-pass snap
  /// or GPS jitter, two in a row are a direction.
  static const int reverseRunFixes = 3;

  /// A fix this far behind the previous one has fallen; this far ahead, it
  /// advances. Wider than the GPS jitter of a bus waiting at a stop.
  static const double _reverseFallMeters = 30;

  /// How far ahead of the fetch time a feed timestamp may be (clock skew).
  static const Duration _maxFutureSkew = Duration(minutes: 2);

  Map<String, BusTrack> get tracks => UnmodifiableMapView(_tracks);
  int get duplicateAssignments => _duplicateAssignments;

  bool isStale(BusTrack track, DateTime now) => now.difference(track.lastFixAt) > staleAfter;

  void ingest(List<TimeTrackVehicle> vehicles, DateTime fetchTime) {
    final canonical = _selectCanonical(vehicles);
    for (final entry in canonical.entries) {
      final v = entry.value;
      if (v.busLat == 0.0 || v.busLon == 0.0) continue;
      _ingestOne(entry.key, v, fetchTime);
    }
    _tracks.removeWhere((_, t) => fetchTime.difference(t.lastFixAt) > dropAfter);
  }

  void _ingestOne(String key, TimeTrackVehicle v, DateTime fetchTime) {
    final gpsTime = _gpsTime(v.positionTimeSeconds, fetchTime);
    // A feed that repeats an old timestamp (or runs ahead of us) must not
    // create or refresh a track. Only a real feed time is judged; the
    // fetch-time fallback is always current.
    if (v.positionTimeSeconds > 0 && v.positionTimeSeconds < Duration.secondsPerDay) {
      if (fetchTime.difference(gpsTime) > dropAfter) return;
      if (gpsTime.difference(fetchTime) > _maxFutureSkew) return;
    }

    var track = _tracks[key];
    if (track != null && _routeChanged(v, track)) track = null;
    if (track != null && !gpsTime.isAfter(track.latest.gpsTime)) return;

    final previous = track?.latest;
    var tripId = v.gtfsTripId.isEmpty ? null : v.gtfsTripId;
    var shapeId = _shapeFor(v, tripId);
    // A missing or unknown trip ID is a gap in the feed, not a new trip:
    // stay on the trip and shape the bus was already tracked on.
    if (previous != null &&
        previous.shapeId != null &&
        (tripId == null || _geometry.shapeIdForTrip(tripId) == null)) {
      tripId = previous.tripId;
      shapeId = previous.shapeId;
    }
    final continuing = previous != null &&
        previous.snapProgress != null &&
        previous.shapeId == shapeId &&
        previous.tripId == tripId;

    double? progress;
    double? snappedLat;
    double? snappedLon;
    var offRoute = false;
    if (shapeId != null) {
      final snap = continuing
          ? _snapContinuing(v, shapeId, previous, gpsTime)
          : _geometry.snap(v.busLat, v.busLon, shapeId, expectedAlong: _geometry.initialHint(v, tripId, shapeId) ??
                  (previous?.shapeId == shapeId ? previous?.snapProgress : null));
      if (snap != null) {
        if (snap.perpendicularDistance > RouteGeometry.offRouteMeters) {
          offRoute = true;
        } else {
          progress = snap.distanceAlongRoute;
          snappedLat = snap.snappedLat;
          snappedLon = snap.snappedLon;
        }
      }
    }

    final snapProgress = progress;
    if (progress != null && track != null && continuing) {
      final run = _backwardRun(track.fixes, progress);
      if (run != null) {
        progress = null;
        snappedLat = null;
        snappedLon = null;
        // A run just confirmed reaches back to its first fallen fix.
        for (var i = track.fixes.length - run; i < track.fixes.length; i++) {
          track.fixes[i] = track.fixes[i].withheld();
        }
      }
    }

    final fix = TrackFix(
      gpsTime: gpsTime,
      fetchTime: fetchTime,
      lat: v.busLat,
      lon: v.busLon,
      heading: _parseHeading(v.heading),
      speedKmh: v.speed,
      tripId: tripId,
      shapeId: shapeId,
      progress: progress,
      snapProgress: snapProgress,
      snappedLat: snappedLat,
      snappedLon: snappedLon,
      offRoute: offRoute,
      // Both adapters (GTFS-Realtime and Fleet View) leave the deviation text
      // empty exactly when no delay was reported; the difference is then 0 and
      // means "unknown", not on time.
      schedDiffMins: v.gtfsStopSequenceDeviation.isEmpty ? null : v.gtfsStopSequenceSchedDifferenceMins,
    );

    if (track == null) {
      _tracks[key] = BusTrack(
        vehicleId: key,
        routeNumber: v.routeNumber,
        routeRun: v.routeRun,
        headsign: v.gtfsTripHeadsign,
        fixes: [fix],
        lastFixAt: fetchTime,
      );
      return;
    }
    track.fixes.add(fix);
    if (track.fixes.length > maxFixes) track.fixes.removeAt(0);
    track
      ..routeRun = v.routeRun.isNotEmpty ? v.routeRun : track.routeRun
      ..headsign = v.gtfsTripHeadsign.isNotEmpty ? v.gtfsTripHeadsign : track.headsign
      ..lastFixAt = fetchTime;
  }

  /// Whether a fix that snapped at [p] on the same trip and shape as the
  /// newest of [fixes] belongs to a backward run (see the class doc), and if
  /// so how many of [fixes] (the newest ones) still need their progress
  /// withheld: none when the run goes on (the newest fix was withheld and
  /// [p] does not advance past it), or the run's earlier fallen fixes when
  /// [p] confirms it, ending [reverseRunFixes] fixes on one trip and shape
  /// that each fell from the one before. Null when not in a run.
  int? _backwardRun(List<TrackFix> fixes, double p) {
    final last = fixes.last;
    if (last.progressWithheld) return p <= last.snapProgress! + _reverseFallMeters ? 0 : null;
    var next = p;
    for (var k = 0; k < reverseRunFixes - 1; k++) {
      final i = fixes.length - 1 - k;
      if (i < 0) return null;
      final f = fixes[i];
      final fp = f.snapProgress;
      if (fp == null || f.tripId != last.tripId || f.shapeId != last.shapeId) return null;
      if (next >= fp - _reverseFallMeters) return null;
      next = fp;
    }
    return reverseRunFixes - 2;
  }

  SnapResult? _snapContinuing(TimeTrackVehicle v, String shapeId, TrackFix previous, DateTime gpsTime) {
    final dt = gpsTime.difference(previous.gpsTime).inMilliseconds / 1000.0;
    final prior = previous.snapProgress!;
    return _geometry.snap(
      v.busLat,
      v.busLon,
      shapeId,
      expectedAlong: prior + (v.speed / 3.6).clamp(0.0, 25.0) * dt,
      minAlong: prior - _windowBackMeters,
      maxAlong: prior + _windowAheadMeters + _windowMaxSpeedMps * dt,
    );
  }

  String? _shapeFor(TimeTrackVehicle v, String? tripId) {
    final byTrip = _geometry.shapeIdForTrip(tripId);
    final shapeId = byTrip ?? _geometry.fallbackShapeId(v);
    if (shapeId == null || !_geometry.hasShape(shapeId)) return null;
    return shapeId;
  }

  /// Route number decides when both sides know it. The routeRun label is not
  /// stable for one route (Fleet View's block vs the route ID fallback).
  bool _routeChanged(TimeTrackVehicle v, BusTrack track) {
    if (v.routeNumber > 0 && track.routeNumber > 0) return v.routeNumber != track.routeNumber;
    return v.routeRun.isNotEmpty && v.routeRun != track.routeRun;
  }

  String? _keyOf(TimeTrackVehicle v) {
    if (v.vehicle.isNotEmpty) return v.vehicle;
    if (v.routeRun.isNotEmpty) return v.routeRun;
    if (v.gtfsTripId.isNotEmpty) return 'trip:${v.gtfsTripId}';
    return null;
  }

  /// The feed can publish two route assignments for one physical vehicle
  /// during interlining. Keep one deterministic, best-supported record.
  Map<String, TimeTrackVehicle> _selectCanonical(List<TimeTrackVehicle> vehicles) {
    _duplicateAssignments = 0;
    final selected = <String, TimeTrackVehicle>{};
    for (final vehicle in vehicles) {
      final key = _keyOf(vehicle);
      if (key == null) continue;
      final current = selected[key];
      if (current != null) _duplicateAssignments++;
      if (current == null || _prefer(vehicle, current, _tracks[key])) selected[key] = vehicle;
    }
    return selected;
  }

  bool _prefer(TimeTrackVehicle candidate, TimeTrackVehicle current, BusTrack? existing) {
    final cPos = candidate.busLat != 0.0 && candidate.busLon != 0.0;
    final kPos = current.busLat != 0.0 && current.busLon != 0.0;
    if (cPos != kPos) return cPos;
    final cStatus = _statusRank(candidate);
    final kStatus = _statusRank(current);
    if (cStatus != kStatus) return cStatus > kStatus;
    final cTrip = _tripRank(candidate);
    final kTrip = _tripRank(current);
    if (cTrip != kTrip) return cTrip > kTrip;
    final cDist = _scheduleDistance(candidate);
    final kDist = _scheduleDistance(current);
    if (cDist != kDist) return cDist < kDist;
    if (existing != null) {
      final cCont = candidate.routeNumber == existing.routeNumber;
      final kCont = current.routeNumber == existing.routeNumber;
      if (cCont != kCont) return cCont;
    }
    return false;
  }

  int _statusRank(TimeTrackVehicle v) {
    final short = v.shortStatus.trim().toUpperCase();
    final long = v.gtfsStopSequenceStatus.trim().toUpperCase();
    if (long == 'NO DATA') return 0;
    if (short == 'OT' || short.startsWith('A') || short.startsWith('B') ||
        long.contains('ON TIME') || long.contains('AHEAD') || long.contains('BEHIND')) {
      return 2;
    }
    return long.isNotEmpty ? 1 : 0;
  }

  int _tripRank(TimeTrackVehicle v) {
    if (v.gtfsTripId.isEmpty) return 0;
    return _geometry.shapeIdForTrip(v.gtfsTripId) != null ? 2 : 1;
  }

  int _scheduleDistance(TimeTrackVehicle v) {
    if (v.positionTimeSeconds <= 0 || v.departureTimeAtClosestStop <= 0) return 1 << 30;
    final raw = (v.positionTimeSeconds - v.departureTimeAtClosestStop).abs() % Duration.secondsPerDay;
    return math.min(raw, Duration.secondsPerDay - raw);
  }

  /// The feed's seconds-since-midnight, placed on the day nearest [fetchTime].
  DateTime _gpsTime(int secondsOfDay, DateTime fetchTime) {
    if (secondsOfDay <= 0 || secondsOfDay >= Duration.secondsPerDay) return fetchTime;
    // The feed's seconds are local wall-clock time, so build the DateTime
    // from calendar fields: adding a Duration is an hour off on DST days.
    DateTime onDay(int dayOffset) =>
        DateTime(fetchTime.year, fetchTime.month, fetchTime.day + dayOffset, 0, 0, secondsOfDay);
    var t = onDay(0);
    final diff = fetchTime.difference(t).inSeconds;
    if (diff > 43200) t = onDay(1);
    if (diff < -43200) t = onDay(-1);
    return t;
  }

  double _parseHeading(String raw) {
    final normalized = raw.trim().toUpperCase();
    final parsed = double.tryParse(normalized);
    if (parsed != null) return parsed % 360;
    const compass = <String, double>{
      'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5, 'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
      'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5, 'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5,
    };
    return compass[normalized] ?? 0.0;
  }
}

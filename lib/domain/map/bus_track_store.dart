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

  Map<String, BusTrack> get tracks => Map.unmodifiable(_tracks);
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
    final tripId = v.gtfsTripId.isEmpty ? null : v.gtfsTripId;
    final shapeId = _shapeFor(v, tripId);

    var track = _tracks[key];
    if (track != null && _routeChanged(v, track)) track = null;
    if (track != null && !gpsTime.isAfter(track.latest.gpsTime)) return;

    final previous = track?.latest;
    final continuing = previous != null &&
        previous.progress != null &&
        previous.shapeId == shapeId &&
        previous.tripId == tripId;

    double? progress;
    double? snappedLat;
    double? snappedLon;
    var offRoute = false;
    if (shapeId != null) {
      final snap = continuing
          ? _snapContinuing(v, shapeId, previous, gpsTime)
          : _geometry.snap(v.busLat, v.busLon, shapeId, expectedAlong: _geometry.initialHint(v, tripId, shapeId));
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
      snappedLat: snappedLat,
      snappedLon: snappedLon,
      offRoute: offRoute,
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

  SnapResult? _snapContinuing(TimeTrackVehicle v, String shapeId, TrackFix previous, DateTime gpsTime) {
    final dt = gpsTime.difference(previous.gpsTime).inMilliseconds / 1000.0;
    final prior = previous.progress!;
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
    var t = DateTime(fetchTime.year, fetchTime.month, fetchTime.day).add(Duration(seconds: secondsOfDay));
    final diff = fetchTime.difference(t).inSeconds;
    if (diff > 43200) t = t.add(const Duration(days: 1));
    if (diff < -43200) t = t.subtract(const Duration(days: 1));
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

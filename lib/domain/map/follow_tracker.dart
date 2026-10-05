import 'dart:math' as math;

import 'bus_tracking_state.dart';
import 'route_geometry.dart';
import 'shape_matcher.dart';

/// Why a follow ended (spec §3.5).
enum FollowEnd { arrived, passedYourStop, tripEnded, lostContact, notFound }

/// What the follow card shows this frame.
class FollowSnapshot {
  const FollowSnapshot({
    required this.vehicleId,
    required this.bus,
    required this.tripId,
    required this.stale,
    required this.lastSeenAgo,
    required this.stops,
    required this.busIndex,
    required this.yourStopIndex,
    required this.stopsToYourStop,
    required this.arrived,
    required this.ended,
    this.shapeId,
    this.progress,
    this.onTrip = true,
  });

  final String vehicleId;

  /// The followed vehicle's latest state; null while it is not in the feed.
  final BusTrackingState? bus;
  final String? tripId;
  final bool stale;
  final Duration? lastSeenAgo;
  final List<TripStop> stops;

  /// The last stop the bus has reached (-1 before the first).
  final int busIndex;

  /// The upcoming visit to your stop on this trip; null when it isn't on it.
  final int? yourStopIndex;
  final int? stopsToYourStop;
  final bool arrived;
  final FollowEnd? ended;

  /// The followed trip's shape.
  final String? shapeId;

  /// The bus's progress along the followed trip as the tracker last placed it.
  final double? progress;

  /// Whether the bus is still on the followed trip.
  final bool onTrip;

  /// The card only needs rebuilding when one of these changes.
  @override
  bool operator ==(Object other) =>
      other is FollowSnapshot &&
      other.vehicleId == vehicleId &&
      other.tripId == tripId &&
      (other.bus == null) == (bus == null) &&
      other.bus?.schedDiffMins == bus?.schedDiffMins &&
      other.bus?.headsign == bus?.headsign &&
      other.stale == stale &&
      other.lastSeenAgo?.inMinutes == lastSeenAgo?.inMinutes &&
      other.busIndex == busIndex &&
      other.yourStopIndex == yourStopIndex &&
      other.stopsToYourStop == stopsToYourStop &&
      other.arrived == arrived &&
      other.ended == ended &&
      (identical(other.stops, stops) || (other.stops.isEmpty && stops.isEmpty));

  @override
  int get hashCode => Object.hash(vehicleId, tripId, bus == null, stale, busIndex, yourStopIndex, stopsToYourStop, arrived, ended);
}

/// Follows exactly one vehicle (spec §3.5): never another, whatever the feed
/// does. Feed it that vehicle's state every frame; it decides stops remaining,
/// arrival (shown for [arrivalLinger], then the end) and the other endings.
///
/// The feed rolls trip IDs over on the timetable clock, so a new trip ID
/// before arrival does not end the follow by itself (spec §3.5, amended in
/// the 3b-3 final review). In order:
/// 1. while the live fix is still on the old trip's shape, ahead of where the
///    bus was, the old trip is kept and placed from that fix (at most
///    [tripChangeGrace]);
/// 2. otherwise, if your stop is ahead of the bus on the new trip, the follow
///    moves to the new trip;
/// 3. otherwise the trip has ended.
///
/// When a trip held in step 1 runs out (an out-and-back turnaround), step 2
/// is tried before it ends.
class FollowTracker {
  FollowTracker({required this.vehicleId, required this.stopsFor, this.snap});

  final String vehicleId;
  final List<TripStop> Function(String tripId, String shapeId) stopsFor;

  /// Snaps a fix to a shape (`RouteGeometry.snap`). Without it a trip change
  /// can't be checked against the old shape and skips straight to step 2.
  final SnapResult? Function(double lat, double lon, String shapeId, {double? expectedAlong, double? minAlong, double? maxAlong})? snap;

  static const double arrivalRadius = 30;
  static const Duration arrivalLinger = Duration(seconds: 10);
  static const double passedMargin = 150;
  static const double tripEndMargin = 30;
  static const Duration notFoundAfter = Duration(seconds: 60);
  static const Duration lostAfter = Duration(minutes: 5);

  /// How long a bus labelled with a new trip may be kept on the old one.
  static const Duration tripChangeGrace = Duration(minutes: 3);

  /// A fix this far behind the last known progress has left the old trip.
  static const double holdBackMargin = 50;

  /// How far ahead of the last known progress the old shape is searched.
  static const double holdAheadWindow = 1500;

  DateTime? _startedAt;
  bool _seen = false;
  String? _tripId;
  String? _shapeId;
  String? _stopsKey;
  List<TripStop> _stops = const [];

  /// Last known progress along the trip; kept while the bus is off route.
  double? _p;

  /// Placement along the trip as of the last frame that knew [_p]. Until a
  /// progress is known there is nothing to carry, so these keep their
  /// "unknown" defaults.
  int _busIndex = -1;
  int? _yourIndex;
  int? _stopsToYourStop;
  DateTime? _arrivedAt;
  DateTime? _holdingSince;
  bool _onTrip = true;
  FollowEnd? _ended;

  /// The not-found clock starts again (the app was paused, so the time it
  /// spent in the background says nothing about the bus).
  void restartClock(DateTime now) {
    if (!_seen) _startedAt = now;
  }

  /// [drawnProgress] is used only while the drawn bus is on the followed
  /// trip ([drawnTripId] null or equal to it).
  FollowSnapshot update({
    required BusTrackingState? bus,
    required double? drawnProgress,
    String? drawnTripId,
    required String? yourStopId,
    required DateTime now,
  }) {
    _startedAt ??= now;
    if (_ended != null) return _snapshot(bus, now);

    if (bus == null) {
      if (_seen) return _end(FollowEnd.lostContact, bus, now);
      if (now.difference(_startedAt!) > notFoundAfter) return _end(FollowEnd.notFound, bus, now);
      return _snapshot(null, now);
    }
    _seen = true;
    if (now.difference(bus.lastGpsTime) > lostAfter) return _end(FollowEnd.lostContact, bus, now);

    // After arrival a different trip is ignored: the bus rolling on to its
    // next trip must not replace "Arrived". Before arrival, see the class doc.
    final trip = bus.currentTripId;
    var foreignTrip = false;
    double? held;
    if (trip != null) {
      if (_tripId == null) {
        _tripId = trip;
      } else if (trip == _tripId) {
        _holdingSince = null;
      } else if (_arrivedAt != null) {
        foreignTrip = true;
      } else {
        held = _holdOnOldShape(bus, now);
        if (held == null) {
          if (_atTerminusYourStop) {
            // Fallback without a usable fix: just short of a terminus your
            // stop is the last stop of counts as the arrival.
            _arrivedAt = now;
            foreignTrip = true;
          } else if (!_moveToTrip(trip, bus, yourStopId)) {
            return _end(FollowEnd.tripEnded, bus, now);
          }
        }
      }
    }
    _onTrip = !foreignTrip;

    double? from;
    if (held != null) {
      from = _p;
      _p = held;
    } else if (!foreignTrip) {
      final shape = bus.shapeId;
      final key = _tripId == null || shape == null ? null : '$_tripId|$shape';
      if (key != null && key != _stopsKey) {
        _stopsKey = key;
        _shapeId = shape;
        _stops = stopsFor(_tripId!, shape!);
      }
      final drawn = drawnTripId == null || drawnTripId == _tripId ? drawnProgress : null;
      _p = drawn ?? bus.progress ?? _p;
    }
    final p = _p;
    if (p != null) {
      var why = _place(p, yourStopId, now, from: from);
      // The held trip ran out (an out-and-back turnaround) while the feed
      // already labels the next one: step 2 before ending.
      if (why == FollowEnd.tripEnded && held != null && trip != null && _moveToTrip(trip, bus, yourStopId)) {
        _onTrip = true;
        why = _place(_p!, yourStopId, now);
      }
      if (why != null) return _end(why, bus, now);
    }
    return _snapshot(bus, now);
  }

  /// Step 1: the live fix's progress on the old trip's shape while it is on
  /// it (within the off-route distance) and not behind the bus; null once it
  /// has left, or after [tripChangeGrace].
  double? _holdOnOldShape(BusTrackingState bus, DateTime now) {
    final snap = this.snap;
    final shape = _shapeId;
    final p = _p;
    if (snap == null || shape == null || p == null) return null;
    final since = _holdingSince ??= now;
    if (now.difference(since) > tripChangeGrace) return null;
    final s = snap(bus.lat, bus.lon, shape,
        expectedAlong: p, minAlong: p - holdBackMargin, maxAlong: p + holdAheadWindow);
    if (s == null || s.perpendicularDistance > RouteGeometry.offRouteMeters) return null;
    if (s.distanceAlongRoute < p - holdBackMargin) return null;
    return s.distanceAlongRoute;
  }

  /// Step 2: follow [trip] instead when your stop is ahead of the bus on it.
  bool _moveToTrip(String trip, BusTrackingState bus, String? yourStopId) {
    final shape = bus.shapeId;
    final p = bus.progress;
    if (shape == null || p == null || yourStopId == null) return false;
    final stops = stopsFor(trip, shape);
    final ahead = stops.any((s) => s.stopId == yourStopId && s.progress != null && s.progress! >= p - passedMargin);
    if (!ahead) return false;
    _tripId = trip;
    _shapeId = shape;
    _stopsKey = '$trip|$shape';
    _stops = stops;
    _busIndex = -1;
    _yourIndex = null;
    _stopsToYourStop = null;
    _holdingSince = null;
    _p = p;
    return true;
  }

  /// Whether your stop is the last placed stop of the trip and the last known
  /// progress is within 60 m before it.
  bool get _atTerminusYourStop {
    final yourIndex = _yourIndex;
    final p = _p;
    if (yourIndex == null || p == null) return false;
    final yp = _stops[yourIndex].progress;
    if (yp == null) return false;
    final lastPlaced = _stops.lastIndexWhere((s) => s.progress != null);
    return yourIndex == lastPlaced && p >= yp - 60;
  }

  /// Works out where progress [p] sits on the trip and returns the ending it
  /// triggers, if any. [from] is the progress of the previous frame when this
  /// one comes from a raw fix (held on the old shape, where fixes are 10-30 s
  /// apart): a stop still ahead at [from] and reached at [p] was driven
  /// through, which is an arrival, not a pass.
  FollowEnd? _place(double p, String? yourStopId, DateTime now, {double? from}) {
    final upcomingFrom = from == null ? p : math.min(p, from);
    // Once arrived, position and count stay frozen at your stop (it can't
    // flicker back, or lose the stop when the bus drives out of the passed
    // margin) until the linger is over.
    if (_arrivedAt == null) {
      _busIndex = -1;
      for (var i = 0; i < _stops.length; i++) {
        final sp = _stops[i].progress;
        if (sp != null && sp <= p + arrivalRadius) _busIndex = i;
      }

      int? yourIndex;
      var onTrip = false;
      if (yourStopId != null) {
        for (var i = 0; i < _stops.length; i++) {
          if (_stops[i].stopId != yourStopId) continue;
          onTrip = true;
          final sp = _stops[i].progress;
          if (sp == null || sp >= upcomingFrom - passedMargin) {
            yourIndex = i;
            break;
          }
        }
      }
      _yourIndex = yourIndex;
      if (yourIndex != null) {
        final yp = _stops[yourIndex].progress;
        if (yp != null && p >= yp - arrivalRadius) _arrivedAt = now;
      } else if (onTrip) {
        _stopsToYourStop = null;
        return FollowEnd.passedYourStop;
      }
    }

    final yourIndex = _yourIndex;
    if (_arrivedAt != null && yourIndex != null) {
      _busIndex = yourIndex;
      _stopsToYourStop = 0;
    } else {
      _stopsToYourStop = yourIndex == null ? null : math.max(0, yourIndex - _busIndex);
    }

    final arrivedAt = _arrivedAt;
    if (arrivedAt != null && now.difference(arrivedAt) >= arrivalLinger) return FollowEnd.arrived;

    if (yourIndex == null) {
      final lastPlaced = _stops.lastWhere((s) => s.progress != null, orElse: () => const TripStop(stopId: '', name: '', sequence: 0, progress: null, departureSeconds: null));
      final lp = lastPlaced.progress;
      if (lp != null && p >= lp - tripEndMargin) return FollowEnd.tripEnded;
    }
    return null;
  }

  FollowSnapshot _end(FollowEnd why, BusTrackingState? bus, DateTime now) {
    _ended = why;
    return _snapshot(bus, now);
  }

  FollowSnapshot _snapshot(BusTrackingState? bus, DateTime now) => FollowSnapshot(
        vehicleId: vehicleId,
        bus: bus,
        tripId: _tripId,
        stale: bus?.status == BusStatus.stale,
        lastSeenAgo: bus == null ? null : now.difference(bus.lastGpsTime),
        stops: _stops,
        busIndex: _busIndex,
        yourStopIndex: _yourIndex,
        stopsToYourStop: _stopsToYourStop,
        arrived: _arrivedAt != null,
        ended: _ended,
        shapeId: _shapeId,
        progress: _p,
        onTrip: _onTrip,
      );
}

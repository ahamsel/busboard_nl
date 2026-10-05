import 'dart:math' as math;

import 'bus_tracking_state.dart';
import 'route_geometry.dart';

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

  /// The card only needs rebuilding when one of these changes.
  @override
  bool operator ==(Object other) =>
      other is FollowSnapshot &&
      other.vehicleId == vehicleId &&
      other.tripId == tripId &&
      (other.bus == null) == (bus == null) &&
      other.bus?.schedDiffMins == bus?.schedDiffMins &&
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
class FollowTracker {
  FollowTracker({required this.vehicleId, required this.stopsFor});

  final String vehicleId;
  final List<TripStop> Function(String tripId, String shapeId) stopsFor;

  static const double arrivalRadius = 30;
  static const Duration arrivalLinger = Duration(seconds: 10);
  static const double passedMargin = 150;
  static const double tripEndMargin = 30;
  static const Duration notFoundAfter = Duration(seconds: 60);
  static const Duration lostAfter = Duration(minutes: 5);

  DateTime? _startedAt;
  bool _seen = false;
  String? _tripId;
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
  FollowEnd? _ended;

  FollowSnapshot update({
    required BusTrackingState? bus,
    required double? drawnProgress,
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

    // A different trip normally ends the follow. After arrival it is ignored:
    // the bus rolling on to its next trip must not replace "Arrived". Before
    // arrival, a change while just short of a terminus your stop is the last
    // stop of counts as the arrival.
    final trip = bus.currentTripId;
    var foreignTrip = false;
    if (trip != null) {
      if (_tripId == null) {
        _tripId = trip;
      } else if (trip != _tripId) {
        if (_arrivedAt == null && _atTerminusYourStop) _arrivedAt = now;
        if (_arrivedAt == null) return _end(FollowEnd.tripEnded, bus, now);
        foreignTrip = true;
      }
    }

    if (!foreignTrip) {
      final shape = bus.shapeId;
      final key = _tripId == null || shape == null ? null : '$_tripId|$shape';
      if (key != null && key != _stopsKey) {
        _stopsKey = key;
        _stops = stopsFor(_tripId!, shape!);
      }
      _p = drawnProgress ?? bus.progress ?? _p;
    }
    final p = _p;
    if (p != null) {
      final why = _place(p, yourStopId, now);
      if (why != null) return _end(why, bus, now);
    }
    return _snapshot(bus, now);
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
  /// triggers, if any.
  FollowEnd? _place(double p, String? yourStopId, DateTime now) {
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
          if (sp == null || sp >= p - passedMargin) {
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
      );
}

import 'dart:convert';

import '../../data/gtfs/gtfs_time.dart';
import '../arrival/arrival_models.dart';

/// Lead times a rider can pick, in minutes (spec §2.1).
const alertLeadChoices = <int>[3, 5, 10];

/// The Android backup alert comes this long after the live one would, so a live watcher always fires first (spec §3.3).
const backupGrace = Duration(minutes: 2);

/// No bell for a bus farther than this. Nearer buses have one while a lead time is still possible (from 4 min).
const alertMaxMinutesAway = 60;

/// Whether [row] gets a bell: at least one lead time is still possible, and the bus is at most 60 min away.
bool canAlert(ArrivalRow row) =>
    row.minutesAway <= alertMaxMinutesAway && leadChoicesFor(row.minutesAway).isNotEmpty;

/// The lead times still possible for a bus [minutesAway] out: only those shorter than the wait.
List<int> leadChoicesFor(int minutesAway) => [for (final m in alertLeadChoices) if (m < minutesAway) m];

/// A service-day time as an instant near [now], counted the way the Board counts minutes (same clock
/// day), moved by a day when that leaves it more than 12 h away: 24:10 at 23:55 is tomorrow 00:10.
DateTime instantOfServiceTime(GtfsTime t, DateTime now) {
  var delta = t.totalSeconds - GtfsTime.fromDateTime(now).totalSeconds;
  while (delta > 12 * 3600) {
    delta -= 24 * 3600;
  }
  while (delta < -12 * 3600) {
    delta += 24 * 3600;
  }
  final base = DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second);
  return base.add(Duration(seconds: delta));
}

/// The one arrival alert a rider has set (spec §3.1).
class ArrivalAlert {
  const ArrivalAlert({
    required this.stopId,
    required this.stopName,
    required this.routeShortName,
    required this.headsign,
    required this.tripId,
    this.routeRun,
    this.vehicle,
    required this.scheduledAt,
    required this.expectedAt,
    required this.live,
    required this.leadMinutes,
    required this.setAt,
    this.lastSeenAt,
    this.firedAt,
  });

  factory ArrivalAlert.fromArrival(
    ArrivalRow row, {
    required String stopId,
    required String stopName,
    required int leadMinutes,
    required DateTime now,
  }) {
    // Whole milliseconds, as JSON keeps them, so the alert is still the same one after a round trip.
    now = DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch);
    final scheduledAt = instantOfServiceTime(row.scheduledTime, now);
    final live = row.isLive && row.predictedTime != null;
    return ArrivalAlert(
      stopId: stopId,
      stopName: stopName,
      routeShortName: row.routeShortName,
      headsign: row.headsign,
      tripId: row.tripId,
      routeRun: row.routeRun,
      vehicle: row.vehicleNumber,
      scheduledAt: scheduledAt,
      expectedAt: live ? instantOfServiceTime(row.displayTime, now) : scheduledAt,
      live: live,
      leadMinutes: leadMinutes,
      setAt: now,
      lastSeenAt: live ? now : null,
    );
  }

  final String stopId;
  final String stopName;
  final String routeShortName;
  final String headsign;

  /// The GTFS trip at this stop.
  final String tripId;

  /// Metrobus's route-run (e.g. "10-4") and bus number, when known.
  final String? routeRun;
  final String? vehicle;

  /// The timetable departure at the stop.
  final DateTime scheduledAt;

  /// The latest expected departure: a live prediction, or [scheduledAt].
  final DateTime expectedAt;

  /// Whether [expectedAt] came from a live prediction.
  final bool live;
  final int leadMinutes;
  final DateTime setAt;

  /// When a live prediction for this trip was last seen.
  final DateTime? lastSeenAt;

  /// When the alert fired; it fires once.
  final DateTime? firedAt;

  /// The app route of this stop's Board, which the alert's notifications open (spec §2.2).
  String get boardRoute => '/board/${Uri.encodeComponent(stopId)}';

  /// When the rider wants the heads-up.
  DateTime get alertAt => expectedAt.subtract(Duration(minutes: leadMinutes));

  /// The same alert (not a replacement), whatever its timing.
  bool isSameAlert(ArrivalAlert other) =>
      other.setAt == setAt && other.tripId == tripId && other.stopId == stopId;

  ArrivalAlert copyWith({
    DateTime? expectedAt,
    bool? live,
    String? routeRun,
    String? vehicle,
    DateTime? lastSeenAt,
    DateTime? firedAt,
  }) =>
      ArrivalAlert(
        stopId: stopId,
        stopName: stopName,
        routeShortName: routeShortName,
        headsign: headsign,
        tripId: tripId,
        routeRun: routeRun ?? this.routeRun,
        vehicle: vehicle ?? this.vehicle,
        scheduledAt: scheduledAt,
        expectedAt: expectedAt ?? this.expectedAt,
        live: live ?? this.live,
        leadMinutes: leadMinutes,
        setAt: setAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        firedAt: firedAt ?? this.firedAt,
      );

  Map<String, Object?> toJson() => {
        'stopId': stopId,
        'stopName': stopName,
        'routeShortName': routeShortName,
        'headsign': headsign,
        'tripId': tripId,
        'routeRun': routeRun,
        'vehicle': vehicle,
        'scheduledAt': scheduledAt.millisecondsSinceEpoch,
        'expectedAt': expectedAt.millisecondsSinceEpoch,
        'live': live,
        'leadMinutes': leadMinutes,
        'setAt': setAt.millisecondsSinceEpoch,
        'lastSeenAt': lastSeenAt?.millisecondsSinceEpoch,
        'firedAt': firedAt?.millisecondsSinceEpoch,
      };

  static ArrivalAlert? fromJson(Map<String, Object?> j) {
    DateTime? at(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    final stopId = j['stopId'], stopName = j['stopName'], route = j['routeShortName'];
    final headsign = j['headsign'], tripId = j['tripId'], lead = j['leadMinutes'], live = j['live'];
    final scheduledAt = at(j['scheduledAt']), expectedAt = at(j['expectedAt']), setAt = at(j['setAt']);
    if (stopId is! String || stopName is! String || route is! String || headsign is! String || tripId is! String) {
      return null;
    }
    if (lead is! int || live is! bool || scheduledAt == null || expectedAt == null || setAt == null) return null;
    final run = j['routeRun'], vehicle = j['vehicle'];
    return ArrivalAlert(
      stopId: stopId,
      stopName: stopName,
      routeShortName: route,
      headsign: headsign,
      tripId: tripId,
      routeRun: run is String ? run : null,
      vehicle: vehicle is String ? vehicle : null,
      scheduledAt: scheduledAt,
      expectedAt: expectedAt,
      live: live,
      leadMinutes: lead,
      setAt: setAt,
      lastSeenAt: at(j['lastSeenAt']),
      firedAt: at(j['firedAt']),
    );
  }

  String encode() => jsonEncode(toJson());

  static ArrivalAlert? decode(String? s) {
    if (s == null) return null;
    try {
      final j = jsonDecode(s);
      return j is Map<String, Object?> ? fromJson(j) : null;
    } on FormatException {
      return null;
    }
  }
}

import 'dart:math' as math;

import '../../data/realtime/metrobus_mobile_api.dart';
import 'arrival_alert.dart';

/// Where an alert's expected time came from on a check.
enum AlertSource { live, timetable, lost }

/// What one check decided (spec §2.4).
class AlertStep {
  const AlertStep({
    required this.alert,
    required this.minutesAway,
    required this.source,
    required this.fire,
    required this.finished,
  });

  /// The alert after this check: re-timed, and with `firedAt` set when [fire].
  final ArrivalAlert alert;
  final int minutesAway;
  final AlertSource source;

  /// Show the alert now (true on exactly one check).
  final bool fire;

  /// Stop watching: the bus is due after the alert, or the 90-minute cap passed.
  final bool finished;
}

/// Pure rules for one arrival alert. Both the Android watcher and the iPhone scheduler run it.
class AlertTracker {
  const AlertTracker();

  /// How long a live bus may be missing before the alert falls back to the timetable.
  static const lostAfter = Duration(minutes: 2);

  /// The longest an alert ever runs.
  static const maxRun = Duration(minutes: 90);

  static const _sameTime = Duration(minutes: 2);
  static const _sameRunWindow = Duration(minutes: 15);

  AlertStep step(ArrivalAlert alert, MetrobusDeparturesResult? result, DateTime now) {
    final rows = result != null && result.succeeded ? result.departures : const <MetrobusDeparture>[];
    final match = find(alert, rows, now: now);
    var a = alert;
    final AlertSource source;
    final predicted = match == null || !match.isRealtime ? null : (match.predictedGtfsTime ?? match.scheduledGtfsTime);
    if (match != null && predicted != null) {
      a = a.copyWith(
        expectedAt: instantOfServiceTime(predicted, now),
        live: true,
        lastSeenAt: now,
        routeRun: match.routeRun.isEmpty ? null : match.routeRun,
        vehicle: match.vehicle.isEmpty ? null : match.vehicle,
      );
      source = AlertSource.live;
    } else if (a.lastSeenAt != null && now.difference(a.lastSeenAt!) < lostAfter) {
      source = AlertSource.live;
    } else if (a.lastSeenAt != null) {
      // Buses rarely get earlier: a gap in a late bus's tracking must not fire early and end the watch.
      final later = a.expectedAt.isAfter(a.scheduledAt) ? a.expectedAt : a.scheduledAt;
      a = a.copyWith(expectedAt: later, live: false);
      source = AlertSource.lost;
    } else {
      a = a.copyWith(expectedAt: a.scheduledAt, live: false);
      source = AlertSource.timetable;
    }

    final fire = a.firedAt == null && !now.isBefore(a.alertAt);
    if (fire) a = a.copyWith(firedAt: now);
    final finished = (a.firedAt != null && !now.isBefore(a.expectedAt)) || now.difference(a.setAt) >= maxRun;
    final minutesAway = math.max(0, a.expectedAt.difference(now).inSeconds ~/ 60);
    return AlertStep(alert: a, minutesAway: minutesAway, source: source, fire: fire, finished: finished);
  }

  /// The alert's departure among one stop's predictions (spec §3.2), or null.
  MetrobusDeparture? find(ArrivalAlert alert, List<MetrobusDeparture> rows, {DateTime? now}) {
    final when = now ?? alert.setAt;
    if (alert.tripId.isNotEmpty) {
      for (final d in rows) {
        if (d.tripId == alert.tripId) return d;
      }
    }
    // A row with its own, different trip id is another bus, whatever else it shares.
    bool otherTrip(MetrobusDeparture d) => alert.tripId.isNotEmpty && d.tripId.isNotEmpty && d.tripId != alert.tripId;
    Duration? offSchedule(MetrobusDeparture d) {
      final s = d.scheduledGtfsTime;
      return s == null ? null : instantOfServiceTime(s, when).difference(alert.scheduledAt).abs();
    }

    final candidates = rows.where((d) => d.routeShortName == alert.routeShortName && !otherTrip(d)).toList();
    bool near(MetrobusDeparture d, Duration window) {
      final off = offSchedule(d);
      return off != null && off <= window;
    }

    final run = alert.routeRun;
    if (run != null && run.isNotEmpty) {
      for (final d in candidates) {
        if (d.routeRun == run && near(d, _sameRunWindow)) return d;
      }
    }
    final bus = alert.vehicle;
    if (bus != null && bus.isNotEmpty) {
      for (final d in candidates) {
        if (d.vehicle == bus && near(d, _sameRunWindow)) return d;
      }
    }
    MetrobusDeparture? best;
    Duration? bestOff;
    for (final d in candidates) {
      final off = offSchedule(d);
      if (off == null || off > _sameTime) continue;
      if (bestOff == null || off < bestOff) {
        best = d;
        bestOff = off;
      }
    }
    return best;
  }
}

import 'dart:math' as math;

import '../../data/gtfs/gtfs_repository.dart';
import 'journey.dart';
import 'place.dart';
import 'ranking.dart';
import 'raptor.dart';
import 'timetable_index.dart';
import 'walking.dart';

enum PlanMode { leaveNow, leaveBy, arriveBy }

class PlanQuery {
  const PlanQuery({required this.from, required this.to, required this.mode, required this.time});
  final Place from;
  final Place to;
  final PlanMode mode;

  /// Leave by / arrive by this; for Leave now, now.
  final DateTime time;
}

sealed class PlanOutcome {}

class PlanFound extends PlanOutcome {
  PlanFound(this.journeys);
  final List<Journey> journeys;
}

class PlanNoJourney extends PlanOutcome {
  PlanNoJourney({this.nextDeparture, this.firstArrival});

  /// Leave by: when the first bus that gets there leaves on the next service day (filled in by the provider).
  final DateTime? nextDeparture;

  /// Arrive by: the earliest anything gets there that day.
  final DateTime? firstArrival;
}

class PlanTooFar extends PlanOutcome {
  PlanTooFar({required this.fromEnd});

  /// True when the start has no stop within 800 m; false when the destination hasn't.
  final bool fromEnd;
}

/// Plans trips on one service day's index (spec §3.3).
class TripPlanner {
  TripPlanner(this.repo, this.index);
  final GtfsRepository repo;
  final TimetableIndex index;

  List<StopOffset> offsetsFor(Place p) {
    switch (p) {
      case StopPlace(:final stopId):
        final s = index.stopIndex[stopId];
        return s == null ? const [] : [StopOffset(s, 0)];
      case PinPlace(:final lat, :final lon):
        return [
          for (var i = 0; i < index.stopIds.length; i++)
            if (repo.stopsById[index.stopIds[i]] case final st?)
              if (haversineMeters(lat, lon, st.stopLat, st.stopLon) case final d when d <= maxAccessMeters)
                StopOffset(i, walkSeconds(d)),
        ];
    }
  }

  PlanOutcome plan(PlanQuery q) {
    final access = offsetsFor(q.from);
    if (access.isEmpty) return PlanTooFar(fromEnd: true);
    final egress = offsetsFor(q.to);
    if (egress.isEmpty) return PlanTooFar(fromEnd: false);
    if (q.from == q.to) return PlanNoJourney();

    final t = secondsInServiceDay(index.serviceDate, q.time);
    final candidates = <Journey>[];
    if (q.mode == PlanMode.arriveBy) {
      var by = t;
      for (var i = 0; i < 4; i++) {
        final found = raptorReverse(index, access: access, egress: egress, arriveBy: by);
        if (found.isEmpty) break;
        candidates.addAll(found);
        by = found.map((j) => j.arrives).reduce(math.min) - 60;
      }
      if (candidates.isEmpty) {
        final any = raptorForward(index, access: access, egress: egress, departAt: -Duration.secondsPerDay);
        if (any.isEmpty) return PlanNoJourney();
        return PlanNoJourney(firstArrival: any.first.at(any.map((j) => j.arrives).reduce(math.min)));
      }
    } else {
      var from = t;
      for (var i = 0; i < 4; i++) {
        final found = raptorForward(index, access: access, egress: egress, departAt: from);
        if (found.isEmpty) break;
        candidates.addAll(found);
        from = found.map((j) => j.departs).reduce(math.min) + 60;
      }
      if (candidates.isEmpty) return PlanNoJourney();
    }
    return PlanFound(rankJourneys(candidates, arriveBy: q.mode == PlanMode.arriveBy));
  }
}

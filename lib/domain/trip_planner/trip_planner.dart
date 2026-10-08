import 'dart:math' as math;

import '../../data/gtfs/gtfs_repository.dart';
import '../../data/realtime/timetrack_api.dart';
import 'journey.dart';
import 'live_overlay.dart';
import 'place.dart';
import 'ranking.dart';
import 'raptor.dart';
import 'timetable_index.dart';
import 'walking.dart';

/// How many times a journey the live times break is planned again before it is dropped.
const maxLiveReplans = 3;

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

  /// Live times for the shown journeys. A ride the live times break (a transfer under a minute, a bus that arrives
  /// before it leaves, a start before now) is dropped and the rest planned again from the ride before it, without
  /// that trip; the new journey is checked in turn, up to [maxLiveReplans] times (spec §3.4). The result is ranked
  /// again (no repeats, at most 5, by departure); empty when none can be shown.
  List<Journey> applyLive(PlanQuery q, List<Journey> js, TimeTrackFetchResult? feed, DateTime now) {
    if (feed == null || !feed.succeeded) return js;
    final nowSeconds = secondsInServiceDay(index.serviceDate, now);
    final earliest = q.mode == PlanMode.leaveBy
        ? math.max(nowSeconds, secondsInServiceDay(index.serviceDate, q.time))
        : nowSeconds;
    final out = <Journey>[];
    for (final original in js) {
      var j = original;
      final skip = <String>{};
      var replans = 0;
      while (true) {
        final live = overlayLive(j, feed, now);
        final cut = firstTightLeg(live, notBefore: earliest);
        if (cut == null) {
          out.add(live);
          break;
        }
        if (replans == maxLiveReplans) break;
        replans++;
        skip.add((live.legs[cut] as RideLeg).tripId);
        // Keep the rides before the broken one (and the walks between them); the rest starts at the last one's end.
        final lastKept = live.legs.sublist(0, cut).lastIndexWhere((l) => l is RideLeg);
        final List<Leg> kept;
        final List<StopOffset> access;
        final int departAt;
        if (lastKept < 0) {
          kept = const [];
          access = offsetsFor(q.from);
          departAt = earliest;
        } else {
          final ride = live.legs[lastKept] as RideLeg;
          final stop = index.stopIndex[ride.alightStopId];
          if (stop == null) break;
          // The kept rides go back on their timetable times, so the next overlay finds them as scheduled.
          kept = j.legs.sublist(0, lastKept + 1);
          access = [StopOffset(stop, 0)];
          departAt = ride.arrives + index.sameStopTransferSeconds[stop];
        }
        final rest = raptorForward(
          index,
          access: access,
          egress: offsetsFor(q.to),
          departAt: departAt,
          skipTrips: skip,
        );
        if (rest.isEmpty) break;
        final tail = rest.reduce((a, b) => a.arrives <= b.arrives ? a : b);
        j = Journey(
          serviceDate: original.serviceDate,
          legs: retimeWalks([...kept, ...tail.legs]),
          replannedForLiveTimes: true,
        );
      }
    }
    // Re-planned journeys can repeat one already in the list, or leave later than the one after them.
    return rankJourneys(out, arriveBy: q.mode == PlanMode.arriveBy);
  }
}

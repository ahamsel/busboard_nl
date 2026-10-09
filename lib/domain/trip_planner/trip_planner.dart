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

/// How far before the earliest start live times look for a late bus that can still be caught (spec §3.4).
const lookBackSeconds = 15 * 60;

/// At most this many look-back searches per refresh.
const maxLookBackPasses = 4;

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

  /// Arrive by: the earliest anything gets there that day, leaving no earlier than now.
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

  /// Plans [q] on the timetable. For Arrive by, [now] (when given) rules out journeys that would have to start
  /// before it, the walk to the first stop included.
  PlanOutcome plan(PlanQuery q, {DateTime? now}) {
    final access = offsetsFor(q.from);
    if (access.isEmpty) return PlanTooFar(fromEnd: true);
    final egress = offsetsFor(q.to);
    if (egress.isEmpty) return PlanTooFar(fromEnd: false);
    if (q.from == q.to) return PlanNoJourney();

    final t = secondsInServiceDay(index.serviceDate, q.time);
    final candidates = <Journey>[];
    if (q.mode == PlanMode.arriveBy) {
      // Negative when now is on an earlier day than the index's; it still rules out last night's late trips
      // (shifted below 0) that have left.
      final notBefore = now == null ? null : secondsInServiceDay(index.serviceDate, now);
      var by = t;
      for (var i = 0; i < 4; i++) {
        final found = raptorReverse(index, access: access, egress: egress, arriveBy: by);
        if (found.isEmpty) break;
        final catchable = notBefore == null ? found : found.where((j) => j.departs >= notBefore).toList();
        candidates.addAll(catchable);
        // Each pass leaves earlier than the one before: once none can still be caught, none later can.
        if (catchable.isEmpty) break;
        by = found.map((j) => j.arrives).reduce(math.min) - 60;
      }
      // Rebuilding the latest departure can get off a bus later than needed (a longer ride, then a longer walk). A
      // forward search from each departure finds the fastest way for it. It goes first, so ranking keeps it and drops
      // the slower copy (a near-duplicate of the same bus otherwise keeps whichever came first).
      final fastest = [
        for (final dep in {for (final j in candidates) j.departs})
          for (final j in raptorForward(index, access: access, egress: egress, departAt: dep))
            if (j.arrives <= t && (notBefore == null || j.departs >= notBefore)) j,
      ];
      candidates.insertAll(0, fastest);
      if (candidates.isEmpty) {
        final any = raptorForward(
          index,
          access: access,
          egress: egress,
          departAt: math.max(notBefore ?? -Duration.secondsPerDay, -Duration.secondsPerDay),
        );
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
  /// that trip; the new journey is checked in turn, up to [maxLiveReplans] times (spec §3.4). For Leave now and Leave
  /// by, a look-back adds late buses that can still be caught (see [_lookBack]). For Arrive by, a
  /// journey that ends up arriving after [PlanQuery.time] is dropped. The result is ranked again (no repeats, at
  /// most 5, by departure); empty when none can be shown.
  List<Journey> applyLive(PlanQuery q, List<Journey> js, TimeTrackFetchResult? feed, DateTime now) {
    if (feed == null || !feed.succeeded) return js;
    final nowSeconds = secondsInServiceDay(index.serviceDate, now);
    final earliest = q.mode == PlanMode.leaveBy
        ? math.max(nowSeconds, secondsInServiceDay(index.serviceDate, q.time))
        : nowSeconds;
    final deadline = q.mode == PlanMode.arriveBy ? secondsInServiceDay(index.serviceDate, q.time) : null;
    final out = <Journey>[];
    for (final original in js) {
      var j = original;
      final skip = <String>{};
      var replans = 0;
      while (true) {
        final live = overlayLive(j, feed, now);
        final cut = firstTightLeg(live, notBefore: earliest);
        if (cut == null) {
          // Arrive by: one the live times (or a re-plan) take past the deadline isn't an option.
          if (deadline == null || live.arrives <= deadline) out.add(live);
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
    // A look-back bus leaves up to lookBackSeconds before earliest; past the live horizon from then, no overlay
    // applies, so it could only find buses that have gone.
    if (q.mode != PlanMode.arriveBy && earliest - nowSeconds <= liveHorizon.inSeconds + lookBackSeconds) {
      out.addAll(_lookBack(q, feed, now, earliest));
    }
    // Re-planned journeys can repeat one already in the list, or leave later than the one after them.
    return rankJourneys(out, arriveBy: q.mode == PlanMode.arriveBy);
  }

  /// A late bus the timetable says has gone can still be due: journeys that, on the timetable, start in the
  /// [lookBackSeconds] before [earliest], kept only when their live times start at or after it and break nothing
  /// (never re-planned). Up to [maxLookBackPasses] searches, each from a minute after the earliest start found.
  List<Journey> _lookBack(PlanQuery q, TimeTrackFetchResult feed, DateTime now, int earliest) {
    final access = offsetsFor(q.from);
    final egress = offsetsFor(q.to);
    final kept = <Journey>[];
    var from = earliest - lookBackSeconds;
    for (var i = 0; i < maxLookBackPasses && from < earliest; i++) {
      final found = raptorForward(index, access: access, egress: egress, departAt: from);
      if (found.isEmpty) break;
      for (final j in found) {
        final live = overlayLive(j, feed, now);
        if (firstTightLeg(live, notBefore: earliest) == null) kept.add(live);
      }
      from = found.map((j) => j.departs).reduce(math.min) + 60;
    }
    return kept;
  }
}

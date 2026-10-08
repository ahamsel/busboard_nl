import 'journey.dart';
import 'timetable_index.dart';

/// At most this many rides, so at most 3 transfers (spec §3.3).
const maxRides = 4;
const _inf = 1 << 40;

sealed class _Label {}

/// Round 0: the walk between the trip's end and this stop (0 s when the end is the stop).
class _Start extends _Label {
  _Start(this.walkSeconds);
  final int walkSeconds;
}

class _Ride extends _Label {
  _Ride(this.pattern, this.trip, this.boardPos, this.alightPos, {required this.viaRide});
  final int pattern, trip, boardPos, alightPos;

  /// The connecting stop (where the rider boarded, in a forward search; where they got off, in a reverse one) was
  /// reached or left by bus, so the same-stop transfer time applied there.
  final bool viaRide;
}

class _Walk extends _Label {
  _Walk(this.otherStop, this.seconds, {required this.atStart});
  final int otherStop, seconds;

  /// The other end is a round-0 start stop (the origin or destination stop itself), not a stop on a bus leg.
  final bool atStart;
}

/// A search's rounds. Each stop has two values per round, as in the reference search: by bus (`ride`) and on foot
/// (`walk`). Values and labels are copied into the next round before it starts.
class _State {
  _State(int rounds, int n, int fill)
      : ride = List.generate(rounds, (_) => List.filled(n, fill)),
        walk = List.generate(rounds, (_) => List.filled(n, fill)),
        rideLabel = List.generate(rounds, (_) => List<_Ride?>.filled(n, null)),
        walkLabel = List.generate(rounds, (_) => List<_Label?>.filled(n, null));
  final List<List<int>> ride, walk;
  final List<List<_Ride?>> rideLabel;
  final List<List<_Label?>> walkLabel;

  void copyRound(int k) {
    ride[k].setAll(0, ride[k - 1]);
    walk[k].setAll(0, walk[k - 1]);
    rideLabel[k].setAll(0, rideLabel[k - 1]);
    walkLabel[k].setAll(0, walkLabel[k - 1]);
  }
}

/// Leave by [departAt]: the earliest arrivals with 1..[rides] rides (spec §3.3). Trips in [skipTrips] are never
/// boarded (the next catchable one is taken instead).
List<Journey> raptorForward(
  TimetableIndex idx, {
  required List<StopOffset> access,
  required List<StopOffset> egress,
  required int departAt,
  int rides = maxRides,
  Set<String> skipTrips = const {},
}) {
  final n = idx.stopIds.length;
  final st = _State(rides + 1, n, _inf);
  final bestRide = List.filled(n, _inf);
  final bestWalk = List.filled(n, _inf);
  var bestTarget = _inf;
  final journeys = <Journey>[];

  // Round 0: at the start stops; from a stop origin, also walk to the stops near it.
  final marked = <int>{};
  for (final a in access) {
    final t = departAt + a.seconds;
    if (t < bestWalk[a.stop]) {
      st.walk[0][a.stop] = t;
      bestWalk[a.stop] = t;
      st.walkLabel[0][a.stop] = _Start(a.seconds);
      marked.add(a.stop);
    }
  }
  for (final a in access.where((a) => a.seconds == 0)) {
    for (final f in idx.footpaths[a.stop]) {
      final t = departAt + f.seconds;
      if (t < bestWalk[f.other]) {
        st.walk[0][f.other] = t;
        bestWalk[f.other] = t;
        st.walkLabel[0][f.other] = _Walk(a.stop, f.seconds, atStart: true);
        marked.add(f.other);
      }
    }
  }

  var current = marked;
  for (var k = 1; k <= rides && current.isNotEmpty; k++) {
    st.copyRound(k);
    // Each pattern is scanned from its earliest stop marked last round.
    final queue = <int, int>{};
    for (final s in current) {
      for (final (p, pos) in idx.patternsAtStop[s]) {
        final q = queue[p];
        if (q == null || pos < q) queue[p] = pos;
      }
    }
    final byBus = <int>{};
    for (final MapEntry(key: pi, value: from) in queue.entries) {
      final p = idx.patterns[pi];
      int? trip;
      var boardPos = -1;
      var viaRide = false;
      for (var pos = from; pos < p.stops.length; pos++) {
        final stop = p.stops[pos];
        if (trip != null) {
          final arr = p.arrivals[trip][pos];
          if (arr < bestRide[stop] && arr < bestTarget) {
            st.ride[k][stop] = arr;
            bestRide[stop] = arr;
            st.rideLabel[k][stop] = _Ride(pi, trip, boardPos, pos, viaRide: viaRide);
            byBus.add(stop);
          }
        }
        // Can an earlier trip of this pattern be caught here?
        final afterBus = st.ride[k - 1][stop] + idx.sameStopTransferSeconds[stop];
        final onFoot = st.walk[k - 1][stop];
        final ready = afterBus < onFoot ? afterBus : onFoot;
        if (ready >= _inf) continue;
        final t = _earliestTrip(p, pos, ready, skipTrips);
        if (t != null && (trip == null || t < trip)) {
          trip = t;
          boardPos = pos;
          viaRide = onFoot > p.departures[t][pos];
        }
      }
    }
    // Walk on from the stops reached by bus this round (never a walk after a walk).
    final onFootNow = <int>{};
    for (final s in byBus) {
      for (final f in idx.footpaths[s]) {
        final t = st.ride[k][s] + f.seconds;
        if (t < bestWalk[f.other] && t < bestTarget) {
          st.walk[k][f.other] = t;
          bestWalk[f.other] = t;
          st.walkLabel[k][f.other] = _Walk(s, f.seconds, atStart: false);
          onFootNow.add(f.other);
        }
      }
    }
    current = {...byBus, ...onFootNow};

    // A better arrival with k rides? Only values this round improved count; older ones were counted already.
    var roundBest = _inf, roundStop = -1, roundEgress = 0;
    var roundWalkTo = -1; // >= 0: the best is a bus to roundStop, then a walk of roundEgress seconds to this stop
    for (final e in egress) {
      final s = e.stop;
      if (st.ride[k][s] < st.ride[k - 1][s] && st.ride[k][s] + e.seconds < roundBest) {
        (roundBest, roundStop, roundEgress, roundWalkTo) = (st.ride[k][s] + e.seconds, s, e.seconds, -1);
      }
      // Bus, then a walk, only to a stop destination: walking on to a pin would be two walks in a row. Taken straight
      // from the bus values, so a walk-in from the origin (round 0) can't hide it.
      if (e.seconds == 0) {
        for (final f in idx.footpathsInto[s]) {
          final from = f.other;
          if (st.ride[k][from] < st.ride[k - 1][from] && st.ride[k][from] + f.seconds < roundBest) {
            (roundBest, roundStop, roundEgress, roundWalkTo) = (st.ride[k][from] + f.seconds, from, f.seconds, s);
          }
        }
      }
    }
    if (roundStop >= 0 && roundBest < bestTarget) {
      bestTarget = roundBest;
      final j = _forwardJourney(idx, st, k, roundStop, true, roundWalkTo < 0 ? roundEgress : 0);
      journeys.add(roundWalkTo < 0
          ? j
          : j.copyWith(
              legs: retimeWalks([...j.legs, _walkLeg(idx.stopIds[roundStop], idx.stopIds[roundWalkTo], roundEgress)])));
    }
  }
  return journeys;
}

/// The first trip leaving position [pos] at or after [ready] (trips are in order and don't overtake), not one of
/// [skip].
int? _earliestTrip(TransitPattern p, int pos, int ready, [Set<String> skip = const {}]) {
  for (var t = 0; t < p.departures.length; t++) {
    if (p.departures[t][pos] >= ready && (skip.isEmpty || !skip.contains(p.tripIds[t]))) return t;
  }
  return null;
}

WalkLeg _walkLeg(String? from, String? to, int seconds) =>
    WalkLeg(fromStopId: from, toStopId: to, seconds: seconds, startSeconds: 0);

RideLeg _rideLeg(TimetableIndex idx, _Ride r) {
  final p = idx.patterns[r.pattern];
  return RideLeg(
    routeId: p.routeId,
    tripId: p.tripIds[r.trip],
    boardStopId: idx.stopIds[p.stops[r.boardPos]],
    alightStopId: idx.stopIds[p.stops[r.alightPos]],
    departs: p.departures[r.trip][r.boardPos],
    arrives: p.arrivals[r.trip][r.alightPos],
    stopCount: r.alightPos - r.boardPos,
  );
}

/// Follows the labels back from the destination stop to the start.
Journey _forwardJourney(TimetableIndex idx, _State st, int k, int stop, bool byBus, int egressSeconds) {
  final legs = <Leg>[]; // last leg first
  if (egressSeconds > 0) legs.add(_walkLeg(idx.stopIds[stop], null, egressSeconds));
  var r = k, s = stop, onBus = byBus;
  while (true) {
    if (onBus) {
      final ride = st.rideLabel[r][s]!;
      legs.add(_rideLeg(idx, ride));
      s = idx.patterns[ride.pattern].stops[ride.boardPos];
      r -= 1;
      onBus = ride.viaRide;
      continue;
    }
    final label = st.walkLabel[r][s]!;
    if (label is _Start) {
      if (label.walkSeconds > 0) legs.add(_walkLeg(null, idx.stopIds[s], label.walkSeconds));
      break;
    }
    final w = label as _Walk;
    legs.add(_walkLeg(idx.stopIds[w.otherStop], idx.stopIds[s], w.seconds));
    s = w.otherStop;
    onBus = !w.atStart;
  }
  return Journey(serviceDate: idx.serviceDate, legs: retimeWalks(legs.reversed.toList()));
}

/// Arrive by [arriveBy]: the latest departures with 1..[rides] rides (spec §3.3).
List<Journey> raptorReverse(
  TimetableIndex idx, {
  required List<StopOffset> access,
  required List<StopOffset> egress,
  required int arriveBy,
  int rides = maxRides,
}) {
  final n = idx.stopIds.length;
  final st = _State(rides + 1, n, -_inf);
  final bestRide = List.filled(n, -_inf);
  final bestWalk = List.filled(n, -_inf);
  var bestOrigin = -_inf;
  final journeys = <Journey>[];

  // Round 0: at the destination stops; to a stop destination, also walk from the stops near it.
  final marked = <int>{};
  for (final e in egress) {
    final t = arriveBy - e.seconds;
    if (t > bestWalk[e.stop]) {
      st.walk[0][e.stop] = t;
      bestWalk[e.stop] = t;
      st.walkLabel[0][e.stop] = _Start(e.seconds);
      marked.add(e.stop);
    }
  }
  for (final e in egress.where((e) => e.seconds == 0)) {
    for (final f in idx.footpathsInto[e.stop]) {
      final t = arriveBy - f.seconds;
      if (t > bestWalk[f.other]) {
        st.walk[0][f.other] = t;
        bestWalk[f.other] = t;
        st.walkLabel[0][f.other] = _Walk(e.stop, f.seconds, atStart: true);
        marked.add(f.other);
      }
    }
  }

  var current = marked;
  for (var k = 1; k <= rides && current.isNotEmpty; k++) {
    st.copyRound(k);
    // Each pattern is scanned backward from its latest stop marked last round.
    final queue = <int, int>{};
    for (final s in current) {
      for (final (p, pos) in idx.patternsAtStop[s]) {
        final q = queue[p];
        if (q == null || pos > q) queue[p] = pos;
      }
    }
    final byBus = <int>{};
    for (final MapEntry(key: pi, value: from) in queue.entries) {
      final p = idx.patterns[pi];
      int? trip;
      var alightPos = -1;
      var viaRide = false;
      for (var pos = from; pos >= 0; pos--) {
        final stop = p.stops[pos];
        if (trip != null) {
          final dep = p.departures[trip][pos];
          if (dep > bestRide[stop] && dep > bestOrigin) {
            st.ride[k][stop] = dep;
            bestRide[stop] = dep;
            st.rideLabel[k][stop] = _Ride(pi, trip, pos, alightPos, viaRide: viaRide);
            byBus.add(stop);
          }
        }
        // Can a later trip of this pattern be taken, getting off here?
        final beforeBus = st.ride[k - 1][stop] - idx.sameStopTransferSeconds[stop];
        final onFoot = st.walk[k - 1][stop];
        final ready = beforeBus > onFoot ? beforeBus : onFoot;
        if (ready <= -_inf) continue;
        final t = _latestTrip(p, pos, ready);
        if (t != null && (trip == null || t > trip)) {
          trip = t;
          alightPos = pos;
          viaRide = onFoot < p.arrivals[t][pos];
        }
      }
    }
    // Walk back from the stops where a bus can be boarded this round (never a walk before a walk).
    final onFootNow = <int>{};
    for (final s in byBus) {
      for (final f in idx.footpathsInto[s]) {
        final t = st.ride[k][s] - f.seconds;
        if (t > bestWalk[f.other] && t > bestOrigin) {
          st.walk[k][f.other] = t;
          bestWalk[f.other] = t;
          st.walkLabel[k][f.other] = _Walk(s, f.seconds, atStart: false);
          onFootNow.add(f.other);
        }
      }
    }
    current = {...byBus, ...onFootNow};

    // A later departure with k rides? Only values this round improved count; older ones were counted already.
    var roundBest = -_inf, roundStop = -1, roundAccess = 0;
    var roundWalkTo = -1; // >= 0: the best is a walk of roundAccess seconds from this stop, then a bus from roundStop
    for (final a in access) {
      final s = a.stop;
      if (st.ride[k][s] > st.ride[k - 1][s] && st.ride[k][s] - a.seconds > roundBest) {
        (roundBest, roundStop, roundAccess, roundWalkTo) = (st.ride[k][s] - a.seconds, s, a.seconds, -1);
      }
      // A walk, then the bus, only from a stop origin: walking from a pin would be two walks in a row. Taken straight
      // from the bus values, so a walk-out to the destination (round 0) can't hide it.
      if (a.seconds == 0) {
        for (final f in idx.footpaths[s]) {
          final to = f.other;
          if (st.ride[k][to] > st.ride[k - 1][to] && st.ride[k][to] - f.seconds > roundBest) {
            (roundBest, roundStop, roundAccess, roundWalkTo) = (st.ride[k][to] - f.seconds, to, f.seconds, s);
          }
        }
      }
    }
    if (roundStop >= 0 && roundBest > bestOrigin) {
      bestOrigin = roundBest;
      final j = _reverseJourney(idx, st, k, roundStop, true, roundWalkTo < 0 ? roundAccess : 0);
      journeys.add(roundWalkTo < 0
          ? j
          : j.copyWith(
              legs: retimeWalks([_walkLeg(idx.stopIds[roundWalkTo], idx.stopIds[roundStop], roundAccess), ...j.legs])));
    }
  }
  return journeys;
}

/// The last trip reaching position [pos] at or before [ready] (trips are in order and don't overtake).
int? _latestTrip(TransitPattern p, int pos, int ready) {
  for (var t = p.arrivals.length - 1; t >= 0; t--) {
    if (p.arrivals[t][pos] <= ready) return t;
  }
  return null;
}

/// Follows the labels forward from the origin stop to the destination.
Journey _reverseJourney(TimetableIndex idx, _State st, int k, int origin, bool byBus, int accessSeconds) {
  final legs = <Leg>[];
  if (accessSeconds > 0) legs.add(_walkLeg(null, idx.stopIds[origin], accessSeconds));
  var r = k, s = origin, onBus = byBus;
  while (true) {
    if (onBus) {
      final ride = st.rideLabel[r][s]!;
      legs.add(_rideLeg(idx, ride));
      s = idx.patterns[ride.pattern].stops[ride.alightPos];
      r -= 1;
      onBus = ride.viaRide;
      continue;
    }
    final label = st.walkLabel[r][s]!;
    if (label is _Start) {
      if (label.walkSeconds > 0) legs.add(_walkLeg(idx.stopIds[s], null, label.walkSeconds));
      break;
    }
    final w = label as _Walk;
    legs.add(_walkLeg(idx.stopIds[s], idx.stopIds[w.otherStop], w.seconds));
    s = w.otherStop;
    onBus = !w.atStart;
  }
  return Journey(serviceDate: idx.serviceDate, legs: retimeWalks(legs));
}

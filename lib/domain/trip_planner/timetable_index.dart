import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../data/gtfs/gtfs_time.dart';
import 'walking.dart';

/// Trips of one route that visit the same stops in the same order and never overtake each other (RAPTOR's "route").
class TransitPattern {
  TransitPattern(this.routeId, this.stops);
  final String routeId;
  final List<int> stops;
  final List<String> tripIds = [];
  final List<List<int>> departures = [];
  final List<List<int>> arrivals = [];

  /// [dep]/[arr] can follow the last trip without overtaking it at any stop.
  bool _canAppend(List<int> dep, List<int> arr) {
    if (tripIds.isEmpty) return true;
    final lastDep = departures.last, lastArr = arrivals.last;
    for (var i = 0; i < dep.length; i++) {
      if (dep[i] < lastDep[i] || arr[i] < lastArr[i]) return false;
    }
    return true;
  }
}

/// A walk to or from [other], in seconds.
class Footpath {
  const Footpath(this.other, this.seconds);
  final int other;
  final int seconds;
}

/// One service day's schedule, arranged for search (spec §3.1). Times are seconds from [serviceDate]'s midnight.
/// Yesterday's trips that run past midnight are included, shifted by −24 h, so a query at 00:10 finds them.
class TimetableIndex {
  TimetableIndex._(this.serviceDate, this.stopIds, this.stopIndex);

  final DateTime serviceDate;
  final List<String> stopIds;
  final Map<String, int> stopIndex;
  final List<TransitPattern> patterns = [];
  late final List<List<(int, int)>> patternsAtStop;
  late final List<List<Footpath>> footpaths;
  late final List<List<Footpath>> footpathsInto;
  late final List<int> sameStopTransferSeconds;

  static TimetableIndex build(GtfsRepository repo, DateTime serviceDate) {
    final day = DateTime(serviceDate.year, serviceDate.month, serviceDate.day);
    final stopIds = repo.stopsById.keys.toList()..sort();
    final stopIndex = {for (var i = 0; i < stopIds.length; i++) stopIds[i]: i};
    final idx = TimetableIndex._(day, stopIds, stopIndex);

    // Each trip's stop times, in sequence order.
    final rowsByTrip = <String, List<StopTimeRow>>{};
    for (final rows in repo.stopTimesByStopId.values) {
      for (final r in rows) {
        rowsByTrip.putIfAbsent(r.tripId, () => []).add(r);
      }
    }
    for (final rows in rowsByTrip.values) {
      rows.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }

    final today = repo.activeServiceIds(day);
    final yesterday = repo.activeServiceIds(DateTime(day.year, day.month, day.day - 1));
    // Per route + stop sequence: (tripId, departures, arrivals), grouped before splitting overtakers.
    final groups = <String, (String, List<int>, List<(String, List<int>, List<int>)>)>{};

    void addTrip(TripInfo trip, List<StopTimeRow> rows, int shift) {
      final stops = <int>[];
      for (final r in rows) {
        final s = stopIndex[r.stopId];
        if (s == null) return; // a stop missing from stops.txt: skip the trip
        stops.add(s);
      }
      if (stops.length < 2) return;
      final key = '${trip.routeId}|${stops.join(',')}';
      final g = groups.putIfAbsent(key, () => (trip.routeId, stops, []));
      g.$3.add((
        trip.tripId,
        [for (final r in rows) GtfsTime.parse(r.departureTime).totalSeconds + shift],
        [for (final r in rows) GtfsTime.parse(r.arrivalTime).totalSeconds + shift],
      ));
    }

    for (final MapEntry(key: tripId, value: rows) in rowsByTrip.entries) {
      final trip = repo.tripsById[tripId];
      if (trip == null) continue;
      if (today.contains(trip.serviceId)) addTrip(trip, rows, 0);
      final pastMidnight = GtfsTime.parse(rows.last.arrivalTime).totalSeconds >= Duration.secondsPerDay;
      if (pastMidnight && yesterday.contains(trip.serviceId)) addTrip(trip, rows, -Duration.secondsPerDay);
    }

    // Trips sorted by first departure; one that would overtake goes to the next pattern that can take it.
    for (final (routeId, stops, trips) in groups.values) {
      trips.sort((a, b) => a.$2.first.compareTo(b.$2.first));
      final split = <TransitPattern>[];
      for (final (id, dep, arr) in trips) {
        var p = split.where((p) => p._canAppend(dep, arr)).firstOrNull;
        if (p == null) {
          p = TransitPattern(routeId, stops);
          split.add(p);
        }
        p.tripIds.add(id);
        p.departures.add(dep);
        p.arrivals.add(arr);
      }
      idx.patterns.addAll(split);
    }

    final n = stopIds.length;
    idx.patternsAtStop = List.generate(n, (_) => <(int, int)>[]);
    for (var pi = 0; pi < idx.patterns.length; pi++) {
      final stops = idx.patterns[pi].stops;
      for (var pos = 0; pos < stops.length; pos++) {
        idx.patternsAtStop[stops[pos]].add((pi, pos));
      }
    }

    // transfers.txt: "from>to" → override seconds, or removed.
    final removed = <String>{};
    final override = <String, int>{};
    for (final rules in repo.transfersByFromStop.values) {
      for (final t in rules) {
        final key = '${t.fromStopId}>${t.toStopId}';
        if (t.transferType == 3) {
          removed.add(key);
        } else if (t.minTransferSeconds != null) {
          override[key] = t.minTransferSeconds!;
        }
      }
    }

    idx.sameStopTransferSeconds = List.generate(n, (s) {
      final o = override['${stopIds[s]}>${stopIds[s]}'];
      return o == null || o < minTransferSeconds ? minTransferSeconds : o;
    });

    idx.footpaths = List.generate(n, (_) => <Footpath>[]);
    idx.footpathsInto = List.generate(n, (_) => <Footpath>[]);
    for (var a = 0; a < n; a++) {
      final sa = repo.stopsById[stopIds[a]]!;
      for (var b = 0; b < n; b++) {
        if (a == b) continue;
        final key = '${stopIds[a]}>${stopIds[b]}';
        if (removed.contains(key)) continue;
        final sb = repo.stopsById[stopIds[b]]!;
        final d = haversineMeters(sa.stopLat, sa.stopLon, sb.stopLat, sb.stopLon);
        if (d > maxTransferMeters) continue;
        final seconds = override[key] ?? walkSeconds(d);
        idx.footpaths[a].add(Footpath(b, seconds));
        idx.footpathsInto[b].add(Footpath(a, seconds));
      }
    }
    return idx;
  }
}

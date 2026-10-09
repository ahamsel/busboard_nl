import 'journey.dart';

/// [a] is at least as good as [b] in every way that matters to the rider.
bool _covers(Journey a, Journey b) =>
    a.departs >= b.departs && a.arrives <= b.arrives && a.rides <= b.rides && a.walkSeconds <= b.walkSeconds;

String _rideKey(Journey j) => j.legs.whereType<RideLeg>().map((r) => r.tripId).join(',');

/// The same rides, leaving within two minutes of each other.
bool _nearDuplicate(Journey a, Journey b) => _rideKey(a) == _rideKey(b) && (a.departs - b.departs).abs() <= 120;

/// [a] makes [b] redundant. When each makes the other redundant, the one not changed for live times wins, so an
/// unchanged option doesn't show "Changed for live times".
bool _beats(Journey a, Journey b) {
  if (!_covers(a, b) && !_nearDuplicate(a, b)) return false;
  final mutual = _covers(b, a) || _nearDuplicate(b, a);
  if (mutual && a.replannedForLiveTimes != b.replannedForLiveTimes) return !a.replannedForLiveTimes;
  return true;
}

/// The shown options (spec §3.1).
///
/// Leave by favours the earliest arrival and fills up with the earliest departures. Arrive by turns that round:
/// the latest departure (closest to the deadline) is the first pick, ties on rides and walking go to the later
/// departure, and the rest fill by latest departure first. Either way the result is sorted by departure.
List<Journey> rankJourneys(List<Journey> candidates, {int max = 5, bool arriveBy = false}) {
  final kept = <Journey>[];
  for (final j in candidates) {
    if (kept.any((u) => _beats(u, j))) continue;
    kept.removeWhere((u) => _beats(j, u));
    kept.add(j);
  }
  if (kept.isEmpty) return const [];
  Journey best(int Function(Journey) key) => kept.reduce((a, b) {
    final ka = key(a), kb = key(b);
    if (ka != kb) return ka < kb ? a : b;
    if (arriveBy && a.departs != b.departs) return a.departs > b.departs ? a : b;
    return a.arrives <= b.arrives ? a : b;
  });
  final picked = <Journey>{
    if (arriveBy) best((j) => -j.departs) else best((j) => j.arrives),
    best((j) => j.rides),
    best((j) => j.walkSeconds),
  };
  final rest = kept.where((j) => !picked.contains(j)).toList()
    ..sort((a, b) => arriveBy ? b.departs.compareTo(a.departs) : a.departs.compareTo(b.departs));
  return [...picked, ...rest].take(max).toList()..sort((a, b) => a.departs.compareTo(b.departs));
}

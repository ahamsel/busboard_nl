import 'journey.dart';

/// [a] is at least as good as [b] in every way that matters to the rider.
bool _covers(Journey a, Journey b) =>
    a.departs >= b.departs && a.arrives <= b.arrives && a.rides <= b.rides && a.walkSeconds <= b.walkSeconds;

String _rideKey(Journey j) => j.legs.whereType<RideLeg>().map((r) => r.tripId).join(',');

/// The shown options (spec §3.1).
List<Journey> rankJourneys(List<Journey> candidates, {int max = 5}) {
  final kept = <Journey>[];
  for (final j in candidates) {
    final redundant = kept.any((u) => _covers(u, j) || _rideKey(u) == _rideKey(j) && (u.departs - j.departs).abs() <= 120);
    if (redundant) continue;
    kept.removeWhere((u) => _covers(j, u));
    kept.add(j);
  }
  if (kept.isEmpty) return const [];
  Journey best(int Function(Journey) key) =>
      kept.reduce((a, b) => key(a) < key(b) || key(a) == key(b) && a.arrives <= b.arrives ? a : b);
  final picked = <Journey>{best((j) => j.arrives), best((j) => j.rides), best((j) => j.walkSeconds)};
  final rest = kept.where((j) => !picked.contains(j)).toList()..sort((a, b) => a.departs.compareTo(b.departs));
  return [...picked, ...rest].take(max).toList()..sort((a, b) => a.departs.compareTo(b.departs));
}

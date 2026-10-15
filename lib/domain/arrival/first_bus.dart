import '../../data/gtfs/gtfs_repository.dart';
import '../../data/gtfs/gtfs_time.dart';

/// The next departure from [stopId] after [now], when it is the first of its service day there: the morning's
/// first bus, or the first of a day that has none until later (spec 2026-10-14 §3.2, "First bus 6:28 AM"). Null when
/// the next departure is a later one of its day (a gap in the middle of the day: "No buses for a while"), or when
/// nothing leaves the stop from yesterday's service through tomorrow's.
DateTime? firstBusAfter(GtfsRepository repo, String stopId, DateTime now) {
  final times = repo.stopTimesByStopId[stopId];
  if (times == null || times.isEmpty) return null;
  final today = DateTime(now.year, now.month, now.day);
  DateTime? next;
  var nextIsFirst = false;
  // Yesterday's service still runs after midnight (24:15 is today's 00:15).
  for (var offset = -1; offset <= 1; offset++) {
    final day = DateTime(today.year, today.month, today.day + offset);
    final services = repo.activeServiceIds(day);
    if (services.isEmpty) continue;
    int? earliest;
    int? soonest;
    for (final st in times) {
      final trip = repo.tripsById[st.tripId];
      if (trip == null || !services.contains(trip.serviceId)) continue;
      final GtfsTime t;
      try {
        t = GtfsTime.parse(st.departureTime);
      } on FormatException {
        continue;
      }
      final s = t.totalSeconds;
      if (earliest == null || s < earliest) earliest = s;
      if (t.toDateTime(day).isAfter(now) && (soonest == null || s < soonest)) soonest = s;
    }
    if (soonest == null) continue;
    final at = GtfsTime.fromSeconds(soonest).toDateTime(day);
    if (next == null || at.isBefore(next)) {
      next = at;
      nextIsFirst = soonest == earliest;
    }
  }
  return nextIsFirst ? next : null;
}

import '../../data/gtfs/gtfs_repository.dart';
import '../../data/gtfs/gtfs_time.dart';

/// How many days ahead [firstBusAfter] looks: a weekend, and a holiday Monday or Friday beside it, fit.
const firstBusDaysAhead = 7;

/// The next departure from [stopId] after [now], when it is the first of its service day there: the morning's
/// first bus, or the first of a day that has none until later (spec 2026-10-14 §3.2, "First bus 6:28 AM"). Null when
/// the next departure is a later one of its day (a gap in the middle of the day: "No buses for a while"), or when
/// nothing leaves the stop from yesterday's service through [firstBusDaysAhead] days ahead.
DateTime? firstBusAfter(GtfsRepository repo, String stopId, DateTime now) {
  final times = repo.stopTimesByStopId[stopId];
  if (times == null || times.isEmpty) return null;
  final today = DateTime(now.year, now.month, now.day);
  DateTime? next;
  var nextIsFirst = false;
  // Yesterday's service still runs after midnight (24:15 is today's 00:15). Days with no service (a weekend, a
  // holiday) are skipped over, up to a week out.
  for (var offset = -1; offset <= firstBusDaysAhead; offset++) {
    final day = DateTime(today.year, today.month, today.day + offset);
    final seconds = repo.departureSecondsOn(stopId, day);
    if (seconds.isEmpty) continue;
    // The first departure of the day still ahead: a binary search, as the list is sorted.
    var lo = 0, hi = seconds.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (GtfsTime.fromSeconds(seconds[mid]).toDateTime(day).isAfter(now)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    if (lo == seconds.length) continue;
    final at = GtfsTime.fromSeconds(seconds[lo]).toDateTime(day);
    if (next == null || at.isBefore(next)) {
      next = at;
      nextIsFirst = seconds[lo] == seconds.first;
    }
  }
  return nextIsFirst ? next : null;
}

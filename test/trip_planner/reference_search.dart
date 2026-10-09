import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:collection/collection.dart';

const _inf = 1 << 40;

/// The earliest arrival at [to] by at least one bus, found the slow, obvious way: Dijkstra over (stop, mode) states.
/// Modes: 0 = not on a bus yet, 1 = just got off a bus, 2 = walked after a bus. The rules are the planner's:
/// a bus after a bus at the same stop needs the stop's transfer time; walking happens only from the origin before the
/// first bus, or right after a bus; never two walks in a row.
int? referenceEarliestArrival(TimetableIndex idx, int from, int to, int departAt) {
  if (from == to) return null;
  final best = <(int, int), int>{};
  final queue = PriorityQueue<(int, int, int)>((a, b) => a.$1.compareTo(b.$1));
  void push(int t, int s, int mode) {
    if (t < (best[(s, mode)] ?? _inf)) {
      best[(s, mode)] = t;
      queue.add((t, s, mode));
    }
  }

  push(departAt, from, 0);
  while (queue.isNotEmpty) {
    final (t, s, mode) = queue.removeFirst();
    if (t > best[(s, mode)]!) continue;
    if (s == to && mode != 0) return t; // the first one settled is the earliest
    final ready = t + (mode == 1 ? idx.sameStopTransferSeconds[s] : 0);
    for (final (pi, pos) in idx.patternsAtStop[s]) {
      final p = idx.patterns[pi];
      for (var trip = 0; trip < p.departures.length; trip++) {
        if (p.departures[trip][pos] < ready) continue;
        for (var q = pos + 1; q < p.stops.length; q++) {
          push(p.arrivals[trip][q], p.stops[q], 1);
        }
        break; // trips in a pattern don't overtake: the first catchable one is the best
      }
    }
    if (mode == 0 && s == from || mode == 1) {
      for (final f in idx.footpaths[s]) {
        push(t + f.seconds, f.other, mode == 0 ? 0 : 2);
      }
    }
  }
  return null;
}

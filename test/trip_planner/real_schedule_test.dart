import 'dart:io';
import 'dart:math';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/raptor.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reference_search.dart';

void main() {
  final dir = Platform.environment['PLANNER_GTFS'];
  test('RAPTOR matches the reference search on 200 random queries, within the speed limits', () async {
    final repo = GtfsRepository();
    await repo.loadFromDirectory(dir!);
    final day = DateTime(2026, 10, 7); // a Wednesday inside the feed (2026-09-07 … 2026-11-01)

    final sw = Stopwatch()..start();
    final idx = TimetableIndex.build(repo, day);
    final buildMs = sw.elapsedMilliseconds;

    final rnd = Random(20261008);
    final served = [for (var s = 0; s < idx.stopIds.length; s++) if (idx.patternsAtStop[s].isNotEmpty) s];
    final mismatches = <String>[];
    var compared = 0, found = 0, worstMs = 0;
    while (compared < 200) {
      final from = served[rnd.nextInt(served.length)];
      final to = served[rnd.nextInt(served.length)];
      if (from == to) continue;
      final at = 6 * 3600 + rnd.nextInt(16 * 3600);
      final ref = referenceEarliestArrival(idx, from, to, at);
      sw.reset();
      final js = raptorForward(idx, access: [StopOffset(from, 0)], egress: [StopOffset(to, 0)], departAt: at, rides: 8);
      worstMs = max(worstMs, sw.elapsedMilliseconds);
      final got = js.isEmpty ? null : js.map((j) => j.arrives).reduce(min);
      compared++;
      if (got != null) found++;
      if (got != ref) mismatches.add('${idx.stopIds[from]}→${idx.stopIds[to]} at $at: raptor $got, reference $ref');
    }
    // ignore: avoid_print
    print('compared $compared ($found with a journey), index ${buildMs}ms, worst search ${worstMs}ms');
    expect(mismatches, isEmpty, reason: mismatches.take(10).join('\n'));
    expect(found, greaterThan(150), reason: 'most random daytime pairs should be reachable');
    expect(buildMs, lessThan(1000), reason: 'index build');
    expect(worstMs, lessThan(100), reason: 'one search');
  }, skip: dir == null ? 'set PLANNER_GTFS=build/gtfs_current to run against the real schedule' : false);
}

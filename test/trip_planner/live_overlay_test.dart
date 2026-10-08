import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/live_overlay.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../arrival_alerts/alert_replay_test.dart' show loadCapture, ReplayPoll;
import '../helpers/feed_fixtures.dart';
import 'test_network.dart';

/// A feed where each trip in [delays] (seconds late) has a fresh bus and a time at every stop but [omitStops].
TimeTrackFetchResult feedWith(TestNetwork net, Map<String, int> delays, DateTime now, {Set<String> omitStops = const {}}) {
  final stopTimes = <String, Map<String, List<FeedStopTime>>>{};
  for (final MapEntry(key: trip, value: delay) in delays.entries) {
    for (final rows in net.repo.stopTimesByStopId.values) {
      for (final r in rows.where((r) => r.tripId == trip && !omitStops.contains(r.stopId))) {
        final scheduled = GtfsTime.parse(r.departureTime).toDateTime(testDay);
        stopTimes.putIfAbsent(trip, () => {})[r.stopId] = [
          FeedStopTime(time: scheduled.add(Duration(seconds: delay)), delay: Duration(seconds: delay)),
        ];
      }
    }
  }
  return fakeFeed([
    for (final MapEntry(key: trip, value: delay) in delays.entries)
      fakeVehicle(trip: trip, id: 'bus-$trip', diff: -(delay ~/ 60), fix: now),
  ], stopTimes: stopTimes);
}

void main() {
  late TestNetwork net;
  late TripPlanner planner;
  final now = DateTime(testDay.year, testDay.month, testDay.day, 8, 0);
  final query = PlanQuery(
    from: StopPlace(stopId: 'A', name: 'Stop A'),
    to: StopPlace(stopId: 'E', name: 'Stop E'),
    mode: PlanMode.leaveBy,
    time: now,
  );
  setUp(() {
    net = TestNetwork();
    planner = TripPlanner(net.repo, TimetableIndex.build(net.repo, testDay));
  });

  /// 1-0 (A 08:00 → C 08:10), then 2-1 (C 08:20 → E 08:28).
  Journey firstAtoE() => (planner.plan(query) as PlanFound).journeys.first;

  test('a late bus shifts its leg and marks it live', () {
    final j = firstAtoE();
    final ride = j.legs.whereType<RideLeg>().first;
    final live = overlayLive(j, feedWith(net, {ride.tripId: 120}, now), now).legs.whereType<RideLeg>().first;
    expect(live.live, isTrue);
    expect(live.departs, ride.departs + 120);
    expect(live.arrives, ride.arrives + 120);
  });

  test('a leg more than 60 minutes away keeps the timetable', () {
    final early = DateTime(testDay.year, testDay.month, testDay.day, 6, 30);
    final j = firstAtoE();
    final out = overlayLive(j, feedWith(net, {j.legs.whereType<RideLeg>().first.tripId: 120}, early), early);
    expect(out.legs.whereType<RideLeg>().first.live, isFalse);
  });

  test("a trip in the feed without the leg's board stop keeps the timetable there", () {
    final j = firstAtoE();
    final ride = j.legs.whereType<RideLeg>().first;
    final live = overlayLive(j, feedWith(net, {ride.tripId: 120}, now, omitStops: {ride.boardStopId}), now)
        .legs
        .whereType<RideLeg>()
        .first;
    expect(live.departs, ride.departs);
    expect(live.arrives, ride.arrives + 120);
  });

  test('a stale bus does not count as live', () {
    final j = firstAtoE();
    final ride = j.legs.whereType<RideLeg>().first;
    final stale = feedWith(net, {ride.tripId: 120}, now.subtract(const Duration(minutes: 10)));
    expect(overlayLive(j, stale, now).legs.whereType<RideLeg>().first.live, isFalse);
  });

  test('a transfer made too tight is planned again, and flagged', () {
    // 1-0 ten minutes late reaches C at 08:20, as 2-1 leaves: the rest goes on 2-2 (C 08:35 → E 08:43).
    final j = firstAtoE();
    final first = j.legs.whereType<RideLeg>().first;
    final live = overlayLive(j, feedWith(net, {first.tripId: 600}, now), now);
    expect(firstTightLeg(live), isNotNull);
    final shown = planner.applyLive(query, [j], feedWith(net, {first.tripId: 600}, now), now).single;
    expect(shown.replannedForLiveTimes, isTrue);
    expect(firstTightLeg(shown), isNull);
    expect(shown.legs.whereType<RideLeg>().last.tripId, '2-2');
    expect(shown.arrives, 8 * 3600 + 2580);
  });

  test('no feed or a failed one: journeys unchanged', () {
    final j = firstAtoE();
    expect(planner.applyLive(query, [j], null, now).single.usesLive, isFalse);
    expect(planner.applyLive(query, [j], const TimeTrackFetchResult.failure(error: 'test'), now).single.usesLive, isFalse);
  });

  final capturePath = Platform.environment['ALERT_CAPTURE'];
  final gtfsDir = Platform.environment['ALERT_GTFS'];
  test(
    'replayed against a capture: live legs stay near the timetable and no transfer is left tight',
    () async {
      final polls = await loadCapture(File(capturePath!).openRead().transform(utf8.decoder).transform(const LineSplitter()));
      final poll = polls.firstWhere((ReplayPoll p) => p.feed != null && p.feed!.succeeded);
      final feed = poll.feed!;
      final repo = GtfsRepository();
      await repo.loadFromDirectory(gtfsDir!);
      final day = DateTime(poll.at.year, poll.at.month, poll.at.day);
      final index = TimetableIndex.build(repo, day);
      final replayPlanner = TripPlanner(repo, index);
      final served = [for (var s = 0; s < index.stopIds.length; s++) if (index.patternsAtStop[s].isNotEmpty) index.stopIds[s]];

      final rnd = Random(1006);
      var planned = 0, replanned = 0, liveLegs = 0;
      while (planned < 20) {
        final from = served[rnd.nextInt(served.length)];
        final to = served[rnd.nextInt(served.length)];
        if (from == to) continue;
        final q = PlanQuery(
          from: StopPlace(stopId: from, name: from),
          to: StopPlace(stopId: to, name: to),
          mode: PlanMode.leaveBy,
          time: poll.at,
        );
        final outcome = replayPlanner.plan(q);
        if (outcome is! PlanFound) continue;
        planned++;
        final shown = replayPlanner.applyLive(q, outcome.journeys, feed, poll.at);
        for (final j in shown) {
          expect(firstTightLeg(j), isNull, reason: '$from→$to');
          if (j.replannedForLiveTimes) replanned++;
          for (final (i, leg) in j.legs.indexed) {
            if (leg is! RideLeg || !leg.live) continue;
            liveLegs++;
            // Compare with the same ride in the journey as planned (the kept legs of a re-planned one keep their places).
            final planned0 = outcome.journeys.firstWhere(
              (o) => i < o.legs.length && o.legs[i] is RideLeg && (o.legs[i] as RideLeg).tripId == leg.tripId && (o.legs[i] as RideLeg).boardStopId == leg.boardStopId,
            );
            final timetable = (planned0.legs[i] as RideLeg).departs;
            expect((leg.departs - timetable).abs(), lessThanOrEqualTo(15 * 60), reason: '${leg.tripId} at ${leg.boardStopId}');
          }
        }
      }
      // ignore: avoid_print
      print('replay: $planned queries, $liveLegs live legs, $replanned journeys planned again');
      expect(liveLegs, greaterThan(0), reason: 'the capture should make at least one leg live');
    },
    skip: capturePath == null || gtfsDir == null ? 'set ALERT_CAPTURE and ALERT_GTFS to replay a capture' : false,
  );
}

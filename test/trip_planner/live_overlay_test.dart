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
TimeTrackFetchResult feedWith(
  TestNetwork net,
  Map<String, int> delays,
  DateTime now, {
  Set<String> omitStops = const {},
}) {
  final stopTimes = <String, Map<String, List<FeedStopTime>>>{};
  for (final MapEntry(key: trip, value: delay) in delays.entries) {
    for (final rows in net.repo.stopTimesByStopId.values) {
      for (final r in rows.where((r) => r.tripId == trip && !omitStops.contains(r.stopId))) {
        final scheduled = GtfsTime.parse(r.departureTime).toDateTime(testDay);
        stopTimes.putIfAbsent(trip, () => {})[r.stopId] = [
          FeedStopTime(
            time: scheduled.add(Duration(seconds: delay)),
            delay: Duration(seconds: delay),
          ),
        ];
      }
    }
  }
  return fakeFeed([
    for (final MapEntry(key: trip, value: delay) in delays.entries)
      fakeVehicle(trip: trip, id: 'bus-$trip', diff: -(delay ~/ 60), fix: now),
  ], stopTimes: stopTimes);
}

bool noDoubleWalks(Journey j) {
  for (var i = 1; i < j.legs.length; i++) {
    if (j.legs[i] is WalkLeg && j.legs[i - 1] is WalkLeg) return false;
  }
  return true;
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
    final live = overlayLive(
      j,
      feedWith(net, {ride.tripId: 120}, now, omitStops: {ride.boardStopId}),
      now,
    ).legs.whereType<RideLeg>().first;
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
    expect(noDoubleWalks(shown), isTrue);
    expect(shown.legs.whereType<RideLeg>().last.tripId, '2-2');
    expect(shown.arrives, 8 * 3600 + 2580);
  });

  test('an early bus (live before now) is not shown: the journey leaves later, on another trip', () {
    final j = firstAtoE();
    final first = j.legs.whereType<RideLeg>().first;
    final shown = planner.applyLive(query, [j], feedWith(net, {first.tripId: -300}, now), now).single;
    expect(shown.departs, greaterThanOrEqualTo(8 * 3600));
    expect(shown.legs.whereType<RideLeg>().map((r) => r.tripId), isNot(contains(first.tripId)));
    expect(shown.replannedForLiveTimes, isTrue);
    expect(firstTightLeg(shown, notBefore: 8 * 3600), isNull);
    expect(noDoubleWalks(shown), isTrue);
  });

  test('a leg with only its board stop live, ending before it starts, stays on the timetable', () {
    // 2-1 (C 08:20 → E 08:28) with C ten minutes late and E unlisted would leave at 08:30, after it arrives.
    final j = firstAtoE();
    final ride = j.legs.whereType<RideLeg>().last;
    final out = overlayLive(j, feedWith(net, {ride.tripId: 600}, now, omitStops: {ride.alightStopId}), now);
    final leg = out.legs.whereType<RideLeg>().last;
    expect((leg.live, leg.departs, leg.arrives), (false, ride.departs, ride.arrives));
    expect(firstTightLeg(out), isNull);
  });

  test('a re-plan after a walking transfer never shows two walks in a row', () {
    final toG = PlanQuery(
      from: StopPlace(stopId: 'A', name: 'Stop A'),
      to: StopPlace(stopId: 'G', name: 'Stop G'),
      mode: PlanMode.leaveBy,
      time: now,
    );
    final j = (planner.plan(toG) as PlanFound).journeys.first;
    expect(j.legs.last, isA<WalkLeg>());
    final first = j.legs.whereType<RideLeg>().first;
    final shown = planner.applyLive(toG, [j], feedWith(net, {first.tripId: -300}, now), now).single;
    expect(shown.replannedForLiveTimes, isTrue);
    expect(noDoubleWalks(shown), isTrue);
    expect(shown.legs.last, isA<WalkLeg>());
    expect(shown.departs, greaterThanOrEqualTo(8 * 3600));
  });

  test('the re-planned tail is itself given live times', () {
    final j = firstAtoE();
    final first = j.legs.whereType<RideLeg>().first;
    final feed = feedWith(net, {first.tripId: 600, '2-2': 120}, now);
    final shown = planner.applyLive(query, [j], feed, now).single;
    final tail = shown.legs.whereType<RideLeg>().last;
    expect(tail.tripId, '2-2');
    expect(tail.live, isTrue);
    expect(tail.departs, 8 * 3600 + 35 * 60 + 120);
    expect(shown.arrives, 8 * 3600 + 2580 + 120);
    expect(shown.replannedForLiveTimes, isTrue);
  });

  test('no feed or a failed one: journeys unchanged', () {
    final j = firstAtoE();
    expect(planner.applyLive(query, [j], null, now).single.usesLive, isFalse);
    expect(
      planner.applyLive(query, [j], const TimeTrackFetchResult.failure(error: 'test'), now).single.usesLive,
      isFalse,
    );
  });

  final capturePath = Platform.environment['ALERT_CAPTURE'];
  final gtfsDir = Platform.environment['ALERT_GTFS'];
  test('replayed against a capture: live legs stay near the timetable and no transfer is left tight', () async {
    final polls = await loadCapture(
      File(capturePath!).openRead().transform(utf8.decoder).transform(const LineSplitter()),
    );
    final poll = polls.firstWhere((ReplayPoll p) => p.feed != null && p.feed!.succeeded);
    final feed = poll.feed!;
    final repo = GtfsRepository();
    await repo.loadFromDirectory(gtfsDir!);
    final day = DateTime(poll.at.year, poll.at.month, poll.at.day);
    final index = TimetableIndex.build(repo, day);
    final replayPlanner = TripPlanner(repo, index);
    final served = [
      for (var s = 0; s < index.stopIds.length; s++)
        if (index.patternsAtStop[s].isNotEmpty) index.stopIds[s],
    ];

    final rnd = Random(1006);
    var planned = 0, replanned = 0, liveLegs = 0;
    var attempts = 0;
    final earliest = secondsInServiceDay(day, poll.at);
    while (planned < 20 && attempts++ < 500) {
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
        expect(firstTightLeg(j, notBefore: earliest), isNull, reason: '$from→$to');
        expect(
          firstTightLeg(overlayLive(j, feed, poll.at), notBefore: earliest),
          isNull,
          reason: '$from→$to overlaid again',
        );
        expect(j.departs, greaterThanOrEqualTo(earliest), reason: '$from→$to starts before the poll');
        expect(noDoubleWalks(j), isTrue, reason: '$from→$to has two walks in a row');
        for (var i = 0; i < j.legs.length; i++) {
          final leg = j.legs[i];
          if (leg is RideLeg) {
            expect(leg.departs, lessThanOrEqualTo(leg.arrives), reason: '$from→$to ride ${leg.tripId}');
          }
          if (i > 0) {
            expect(leg.startSeconds, greaterThanOrEqualTo(j.legs[i - 1].endSeconds), reason: '$from→$to leg $i');
          }
        }
        if (j.replannedForLiveTimes) replanned++;
        for (final leg in j.legs) {
          if (leg is! RideLeg || !leg.live) continue;
          liveLegs++;
          // The timetable time of this visit: the trip's row at the board stop nearest the live time.
          final timetable = [
            for (final r in repo.stopTimesByStopId[leg.boardStopId]!)
              if (r.tripId == leg.tripId) GtfsTime.parse(r.departureTime).totalSeconds,
          ].reduce((a, b) => (a - leg.departs).abs() <= (b - leg.departs).abs() ? a : b);
          expect(
            (leg.departs - timetable).abs(),
            lessThanOrEqualTo(15 * 60),
            reason: '${leg.tripId} at ${leg.boardStopId}',
          );
        }
      }
    }
    expect(planned, 20, reason: 'found 20 plannable queries within 500 attempts');
    // ignore: avoid_print
    print('replay: $planned queries, $liveLegs live legs, $replanned journeys planned again');
    expect(liveLegs, greaterThan(0), reason: 'the capture should make at least one leg live');
  }, skip: capturePath == null || gtfsDir == null ? 'set ALERT_CAPTURE and ALERT_GTFS to replay a capture' : false);
}

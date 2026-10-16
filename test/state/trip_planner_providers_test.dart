import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../trip_planner/live_overlay_test.dart' show feedWith;
import '../trip_planner/test_network.dart';

void main() {
  late ProviderContainer c;
  late DateTime clock;
  // The live feed is down by default: plans use the timetable.
  late Future<http.Response> Function(http.Request) liveAnswer;
  DateTime at(int h, int m) => DateTime(testDay.year, testDay.month, testDay.day, h, m);
  StopPlace stop(String id) => StopPlace(stopId: id, name: 'Stop $id');

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final net = TestNetwork();
    clock = at(8, 1);
    liveAnswer = (_) async => http.Response('', 503);
    c = ProviderContainer(
      overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => net.repo),
        plannerClockProvider.overrideWithValue(() => clock),
        timetableIndexBuilderProvider.overrideWithValue((repo, day) async => TimetableIndex.build(repo, day)),
        timetrackApiProvider.overrideWithValue(TimeTrackApi(client: MockClient((r) => liveAnswer(r)))),
      ],
    );
  });
  tearDown(() => c.dispose());

  Future<T> read<T>(ProviderListenable<AsyncValue<T>> p, Future<T> Function() future) async {
    final sub = c.listen(p, (_, _) {});
    addTearDown(sub.close);
    return future();
  }

  Future<PlanOutcome?> results() => read(planResultsProvider, () => c.read(planResultsProvider.future));

  test('no plan until both ends are set; then leave now takes the next bus', () async {
    expect(await results(), isNull);
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'));
    final out = await results() as PlanFound;
    expect(out.journeys.first.departs, 8 * 3600 + 600);
    expect(out.journeys.any((j) => j.usesLive), isFalse);
  });

  test('swap exchanges the ends', () {
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'))
      ..swap();
    expect((c.read(planQueryProvider).from as StopPlace).stopId, 'C');
  });

  group('a time for Leave by and Arrive by', () {
    test('the default is now + 30 min, rounded up to 5 minutes', () {
      expect(defaultPlanTime(at(8, 1)), at(8, 35)); // 8:01 + 30 = 8:31
      expect(defaultPlanTime(at(8, 30)), at(9, 0), reason: 'already on a 5-minute mark');
      expect(defaultPlanTime(DateTime(testDay.year, testDay.month, testDay.day, 8, 30, 20)), at(9, 5),
          reason: 'seconds past the mark round up');
      expect(c.read(planDefaultTimeProvider), at(8, 35));
    });

    test('switching with no time picked keeps none: the plan uses the default', () {
      final q = c.read(planQueryProvider.notifier)
        ..setFrom(stop('A'))
        ..setTo(stop('C'))
        ..setMode(PlanMode.arriveBy);
      final draft = c.read(planQueryProvider);
      expect(draft.time, isNull);
      expect(draft.usesDefaultTime, isTrue);
      expect(draft.toQuery(at(8, 1))!.time, at(8, 35));
      expect(draft.toQuery(at(8, 1), defaultTime: at(9, 0))!.time, at(9, 0));
      q.setMode(PlanMode.leaveNow);
      expect(c.read(planQueryProvider).usesDefaultTime, isFalse);
      expect(c.read(planQueryProvider).toQuery(at(8, 1))!.time, at(8, 1));
    });

    test('a time picked is kept, and Leave now ignores it', () {
      final q = c.read(planQueryProvider.notifier)
        ..setFrom(stop('A'))
        ..setTo(stop('C'))
        ..setTime(at(8, 25))
        ..setMode(PlanMode.arriveBy);
      expect(c.read(planQueryProvider).time, at(8, 25));
      expect(c.read(planQueryProvider).usesDefaultTime, isFalse);
      q.setMode(PlanMode.leaveNow);
      expect(c.read(planQueryProvider).toQuery(at(8, 1))!.time, at(8, 1));
      q.setMode(PlanMode.leaveBy);
      expect(c.read(planQueryProvider).toQuery(at(9, 40))!.time, at(8, 25), reason: 'a picked time does not move');
    });

    test('so the first Arrive by view has buses', () async {
      c.read(planQueryProvider.notifier)
        ..setFrom(stop('A'))
        ..setTo(stop('C'))
        ..setMode(PlanMode.arriveBy);
      final out = await results() as PlanFound;
      expect(out.journeys, isNotEmpty);
      expect(out.journeys.every((j) => j.arrives <= 8 * 3600 + 35 * 60), isTrue);
    });
  });

  test('arrive by 8:25: every option arrives in time', () async {
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'))
      ..setMode(PlanMode.arriveBy)
      ..setTime(at(8, 25));
    final out = await results() as PlanFound;
    expect(out.journeys.every((j) => j.arrives <= 8 * 3600 + 1500), isTrue);
  });

  test('arrive by 8:40 asked at 8:30, the feed down: no bus that has already left', () async {
    clock = at(8, 30);
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'))
      ..setMode(PlanMode.arriveBy)
      ..setTime(at(8, 40));
    final out = await results() as PlanFound;
    expect(out.journeys.map((j) => j.departs), [8 * 3600 + 1800]);
  });

  test('arrive by 8:25 asked at 8:30: no journey, and the earliest arrival is after now', () async {
    clock = at(8, 30);
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'))
      ..setMode(PlanMode.arriveBy)
      ..setTime(at(8, 25));
    final out = await results() as PlanNoJourney;
    expect(out.firstArrival, at(8, 40));
  });

  group('arrive by where the live times push every option past the deadline', () {
    Future<PlanOutcome?> arriveBy(TimeTrackFetchResult Function(TestNetwork net) feed, {DateTime? asked}) async {
      final net = TestNetwork();
      final live = ProviderContainer(
        overrides: [
          gtfsRepositoryProvider.overrideWith((ref) async => net.repo),
          plannerClockProvider.overrideWithValue(() => asked ?? at(8, 30)),
          timetableIndexBuilderProvider.overrideWithValue((repo, day) async => TimetableIndex.build(repo, day)),
          plannerLiveFeedProvider.overrideWith((ref) async => feed(net)),
        ],
      );
      addTearDown(live.dispose);
      live.read(planQueryProvider.notifier)
        ..setFrom(stop('A'))
        ..setTo(stop('C'))
        ..setMode(PlanMode.arriveBy)
        ..setTime(at(8, 40));
      final sub = live.listen(planResultsProvider, (_, _) {});
      addTearDown(sub.close);
      // The first answer plans on the timetable; wait for the one with the feed.
      await live.read(plannerLiveFeedProvider.future);
      await Future<void>.delayed(Duration.zero);
      return live.read(planResultsProvider.future);
    }

    test('the earliest arrival is the live one, from now', () async {
      // The only bus in time, 1-3 (8:30 → 8:40), runs 2 min late: it gets to C at 8:42.
      final out = await arriveBy((net) => feedWith(net, {'1-3': 120}, at(8, 30)));
      expect(out, isA<PlanNoJourney>());
      expect((out as PlanNoJourney).firstArrival, at(8, 42));
    });

    test('a late bus the fallback finds that does make the deadline is offered, not named as too late', () async {
      // Asked at 8:25: the timetable's only option, 1-3 (8:30 → 8:40), runs 3 min late and misses 8:40; 1-2, due at
      // 8:20 but 6 min late, leaves at 8:26 and gets there at 8:36.
      final out = await arriveBy((net) => feedWith(net, {'1-2': 360, '1-3': 180}, at(8, 25)), asked: at(8, 25));
      expect(out, isA<PlanFound>());
      final js = (out as PlanFound).journeys;
      expect(js, isNotEmpty);
      expect(js.every((j) => j.arrives <= 8 * 3600 + 2400), isTrue);
      expect(js.every((j) => j.departs >= 8 * 3600 + 1500), isTrue);
      expect(js.first.legs.whereType<RideLeg>().first.tripId, '1-2');
    });

    test('nothing left to take at all: no earliest arrival', () async {
      // Every bus still to come, in reach of the timetable, is shown leaving before now: none can be taken.
      final out = await arriveBy(
        (net) => feedWith(net, {'1-3': -1500, '1-4': -1500, '1-5': -1500}, at(8, 30)),
      );
      expect(out, isA<PlanNoJourney>());
      expect((out as PlanNoJourney).firstArrival, isNull);
    });
  });

  test('leave by 22:00 with nothing left today: the first bus tomorrow', () async {
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'))
      ..setMode(PlanMode.leaveBy)
      ..setTime(at(22, 0));
    final out = await results() as PlanNoJourney;
    expect(out.nextDeparture, DateTime(testDay.year, testDay.month, testDay.day + 1, 8, 0));
  });

  test('saved trips: add once; the same ends again stay one', () async {
    await read(savedTripsProvider, () => c.read(savedTripsProvider.future));
    final n = c.read(savedTripsProvider.notifier);
    expect(await n.add(SavedTrip(id: '1', name: 'A → C', from: stop('A'), to: stop('C'))), isTrue);
    expect(await n.add(SavedTrip(id: '2', name: 'again', from: stop('A'), to: stop('C'))), isFalse);
    expect((await c.read(savedTripsProvider.future)).map((t) => t.id), ['1']);
  });

  test('two adds at once with different ends both end up saved', () async {
    await read(savedTripsProvider, () => c.read(savedTripsProvider.future));
    final n = c.read(savedTripsProvider.notifier);
    final first = n.add(SavedTrip(id: '1', name: 'A → C', from: stop('A'), to: stop('C')));
    final second = n.add(SavedTrip(id: '2', name: 'C → E', from: stop('C'), to: stop('E')));
    expect(await Future.wait([first, second]), [true, true]);
    expect((await c.read(savedTripsProvider.future)).map((t) => t.id), ['1', '2']);
    // And on the phone, not just in the provider.
    expect((await c.read(savedTripStoreProvider).read()).map((t) => t.id), ['1', '2']);
  });

  test('rename and remove run in order after an add, without awaiting between', () async {
    await read(savedTripsProvider, () => c.read(savedTripsProvider.future));
    final n = c.read(savedTripsProvider.notifier);
    final adds = [
      n.add(SavedTrip(id: '1', name: 'one', from: stop('A'), to: stop('C'))),
      n.add(SavedTrip(id: '2', name: 'two', from: stop('C'), to: stop('E'))),
      n.rename('1', 'Work'),
      n.remove('2'),
    ];
    await Future.wait(adds);
    final saved = await c.read(savedTripsProvider.future);
    expect(saved.map((t) => (t.id, t.name)), [('1', 'Work')]);
  });

  test("a saved trip's next departures: up to 3, the first the next bus", () async {
    await read(savedTripsProvider, () => c.read(savedTripsProvider.future));
    await c.read(savedTripsProvider.notifier).add(SavedTrip(id: '1', name: 'A → C', from: stop('A'), to: stop('C')));
    final next = await read(savedTripNextProvider('1'), () => c.read(savedTripNextProvider('1').future));
    expect(next.length, inInclusiveRange(1, 3));
    expect(next.first.departs, 8 * 3600 + 600);
  });

  test('a live feed that never answers: the timetable results come at once', () async {
    liveAnswer = (_) => Completer<http.Response>().future;
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'));
    final out = await results().timeout(const Duration(seconds: 2)) as PlanFound;
    expect(out.journeys.first.departs, 8 * 3600 + 600);
    expect(out.journeys.any((j) => j.usesLive), isFalse);
  });

  test("a live feed that never answers: a saved trip's departures come at once", () async {
    liveAnswer = (_) => Completer<http.Response>().future;
    await read(savedTripsProvider, () => c.read(savedTripsProvider.future));
    await c.read(savedTripsProvider.notifier).add(SavedTrip(id: '1', name: 'A → C', from: stop('A'), to: stop('C')));
    final next = await read(
      savedTripNextProvider('1'),
      () => c.read(savedTripNextProvider('1').future),
    ).timeout(const Duration(seconds: 2));
    expect(next.first.departs, 8 * 3600 + 600);
  });

  group('the schedule', () {
    // Settings, Refresh schedule: the second load fails while offline, or brings a new schedule.
    late int builds;
    ProviderContainer withSchedule(Future<GtfsRepository> Function(int load) schedule) {
      var loads = 0;
      builds = 0;
      final r = ProviderContainer(
        overrides: [
          gtfsRepositoryProvider.overrideWith((ref) => schedule(++loads)),
          plannerClockProvider.overrideWithValue(() => clock),
          timetableIndexBuilderProvider.overrideWithValue((repo, day) async {
            builds++;
            return TimetableIndex.build(repo, day);
          }),
          timetrackApiProvider.overrideWithValue(TimeTrackApi(client: MockClient((r) => liveAnswer(r)))),
        ],
      );
      addTearDown(r.dispose);
      r.listen(planResultsProvider, (_, _) {});
      return r;
    }

    test('that fails to reload keeps the one loaded: a new trip still plans', () async {
      final r = withSchedule((load) async => load > 1 ? throw StateError('offline') : TestNetwork().repo);
      r.read(planQueryProvider.notifier)
        ..setFrom(stop('A'))
        ..setTo(stop('C'));
      expect(await r.read(planResultsProvider.future), isA<PlanFound>());
      r.invalidate(gtfsRepositoryProvider);
      await expectLater(r.read(gtfsRepositoryProvider.future), throwsStateError, reason: 'the reload failed');
      r.read(planQueryProvider.notifier).setTo(stop('B'));
      final out = await r.read(planResultsProvider.future);
      expect(out, isA<PlanFound>(), reason: 'not an error until a relaunch');
      expect((out as PlanFound).journeys.first.departs, 8 * 3600 + 600);
    });

    test('that reloads moves the planner to the new one', () async {
      final schedules = [TestNetwork().repo, TestNetwork().repo];
      final reloaded = Completer<void>();
      final r = withSchedule((load) async {
        if (load > 1) await reloaded.future; // a reload takes a while: parsing, or a download first
        return schedules[load - 1];
      });
      r.listen(tripPlannerProvider(testDay), (_, _) {});
      expect((await r.read(tripPlannerProvider(testDay).future)).repo, same(schedules[0]));
      r.invalidate(gtfsRepositoryProvider);
      await pumpEventQueue(); // the planner starts again while the reload runs
      expect(r.read(gtfsRepositoryProvider).isLoading, isTrue);
      reloaded.complete();
      expect(await r.read(gtfsRepositoryProvider.future), same(schedules[1]));
      expect((await r.read(tripPlannerProvider(testDay).future)).repo, same(schedules[1]),
          reason: 'not the old schedule, kept while the reload ran');
      await pumpEventQueue();
      expect(builds, 2, reason: 'one planner per schedule, not a second as the reload lands');
    });

    test('that fails its first load: the plan is an error', () async {
      final r = withSchedule((_) async => throw StateError('no schedule'));
      r.read(planQueryProvider.notifier)
        ..setFrom(stop('A'))
        ..setTo(stop('C'));
      await expectLater(r.read(tripPlannerProvider(testDay).future), throwsStateError);
      await expectLater(r.read(planResultsProvider.future), throwsStateError);
    });
  });

  test('the real background build sends the slim repository and returns the day index', () async {
    final index = await buildIndexInBackground(TestNetwork().repo, testDay);
    expect(index.serviceDate, testDay);
    final p1 = index.patterns.singleWhere((p) => p.routeId == '1');
    expect(p1.tripIds.length, 6);
    expect(p1.stops.length, 3);
  });
}

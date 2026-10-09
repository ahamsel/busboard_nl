import 'dart:async';

import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
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

  test('the real background build sends the slim repository and returns the day index', () async {
    final index = await buildIndexInBackground(TestNetwork().repo, testDay);
    expect(index.serviceDate, testDay);
    final p1 = index.patterns.singleWhere((p) => p.routeId == '1');
    expect(p1.tripIds.length, 6);
    expect(p1.stops.length, 3);
  });
}

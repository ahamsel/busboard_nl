import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTimeTrack extends TimeTrackApi {
  @override
  Future<TimeTrackFetchResult> fetchVehiclesResult() async =>
      TimeTrackFetchResult.success(const [], source: LiveDataSource.gtfsRealtime);
}

/// A live feed that answers after [delay], counting its calls.
class _SlowTimeTrack extends TimeTrackApi {
  _SlowTimeTrack(this.delay);
  final Duration delay;
  int calls = 0;
  @override
  Future<TimeTrackFetchResult> fetchVehiclesResult() async {
    calls++;
    await Future<void>.delayed(delay);
    return TimeTrackFetchResult.success(const [], source: LiveDataSource.gtfsRealtime);
  }
}

class _FakeMobile extends MetrobusMobileApi {
  final asked = <String>[];
  @override
  Future<MetrobusDeparturesResult> fetchDeparturesResult(String stopId, {bool forceRefresh = false}) async {
    asked.add(stopId);
    return MetrobusDeparturesResult.failure();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('route filter: empty is all; toggling adds and removes; showAll clears', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(mapRouteFilterProvider.notifier);
    expect(c.read(mapRouteFilterProvider), isEmpty);
    n.toggle(10);
    expect(c.read(mapRouteFilterProvider), {10});
    n.toggle(2);
    expect(c.read(mapRouteFilterProvider), {10, 2});
    n.toggle(10);
    expect(c.read(mapRouteFilterProvider), {2});
    n.showAll();
    expect(c.read(mapRouteFilterProvider), isEmpty);
  });

  test('selection holds a stop or a bus, by value', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(mapSelectionProvider.notifier).select(const StopSelection('1150'));
    expect(c.read(mapSelectionProvider), const StopSelection('1150'));
    c.read(mapSelectionProvider.notifier).select(const BusSelection('2573'));
    expect(c.read(mapSelectionProvider), const BusSelection('2573'));
    expect(const BusSelection('2573') == const BusSelection('2574'), isFalse);
    c.read(mapSelectionProvider.notifier).clear();
    expect(c.read(mapSelectionProvider), isNull);
  });

  test('stop arrivals ask the stop-prediction feed for that stop', () async {
    final mobile = _FakeMobile();
    final c = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
      timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
      metrobusMobileApiProvider.overrideWithValue(mobile),
    ]);
    addTearDown(c.dispose);
    await c.read(gtfsRepositoryProvider.future);
    c.listen(stopArrivalsProvider('1150'), (_, _) {});
    expect(await c.read(stopArrivalsProvider('1150').future), isEmpty);
    expect(mobile.asked, ['1150']);
  });

  group('stop arrivals before the schedule is loaded', () {
    testWidgets('they are loading, not an empty list, until the schedule is in; then they load', (tester) async {
      final mobile = _FakeMobile();
      final schedule = Completer<GtfsRepository>();
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) => schedule.future),
        timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
        metrobusMobileApiProvider.overrideWithValue(mobile),
      ]);
      c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      final loading = c.read(stopArrivalsProvider('1150'));
      expect(loading.isLoading, isTrue);
      expect(loading.hasValue, isFalse, reason: 'an empty list would read as "No upcoming departures"');
      expect(mobile.asked, isEmpty, reason: 'nothing to show them against yet');
      schedule.complete(GtfsRepository());
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(stopArrivalsProvider('1150')).value, isEmpty);
      expect(mobile.asked, ['1150']);
      c.dispose();
    });

    testWidgets('a schedule that fails to reload keeps the one loaded: departures stay data, poll after poll',
        (tester) async {
      // Settings, Refresh schedule, while offline: the second load fails.
      final mobile = _FakeMobile();
      var loads = 0;
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async {
          if (++loads > 1) throw StateError('offline');
          return GtfsRepository();
        }),
        timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
        metrobusMobileApiProvider.overrideWithValue(mobile),
      ]);
      c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(stopArrivalsProvider('1150')).hasValue, isTrue);
      c.invalidate(gtfsRepositoryProvider);
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(gtfsRepositoryProvider).hasError, isTrue, reason: 'the reload failed');
      final asked = mobile.asked.length;
      await tester.pump(const Duration(seconds: 6)); // the next poll
      expect(mobile.asked.length, greaterThan(asked), reason: 'polling goes on');
      final after = c.read(stopArrivalsProvider('1150'));
      expect(after.hasError, isFalse, reason: 'not "Offline" on the old schedule');
      expect(after.hasValue, isTrue);
      c.dispose();
    });

    testWidgets('a schedule that fails to load is an error, not an empty list', (tester) async {
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => throw StateError('no schedule')),
        timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
        metrobusMobileApiProvider.overrideWithValue(_FakeMobile()),
      ]);
      c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(stopArrivalsProvider('1150')).hasError, isTrue);
      c.dispose();
    });
  });

  group('stop arrivals cache', () {
    testWidgets("your stop's arrivals survive nobody watching; other stops' do not", (tester) async {
      final mobile = _FakeMobile();
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
        metrobusMobileApiProvider.overrideWithValue(mobile),
      ]);
      await c.read(gtfsRepositoryProvider.future);
      await c.read(settingsProvider.notifier).setSelectedStop('1150');

      // Your stop: watched, then not watched (a bus card is showing).
      final mine = c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(mobile.asked, ['1150']);
      mine.close();
      await tester.pump(const Duration(milliseconds: 100));
      final cached = c.read(stopArrivalsProvider('1150'));
      expect(cached.hasValue, isTrue, reason: 'no skeleton on the way back');
      expect(mobile.asked, ['1150'], reason: 'and no second fetch');

      // Nobody watching: no polling either.
      await tester.pump(const Duration(seconds: 30));
      expect(mobile.asked, ['1150']);

      // Another stop is dropped when its last listener goes.
      final other = c.listen(stopArrivalsProvider('2000'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      other.close();
      await tester.pump(const Duration(milliseconds: 100));
      mobile.asked.clear();
      c.listen(stopArrivalsProvider('2000'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(mobile.asked, ['2000'], reason: 'fetched afresh');
      c.dispose();
    });

    testWidgets('choosing another stop lets the old one go', (tester) async {
      final mobile = _FakeMobile();
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
        metrobusMobileApiProvider.overrideWithValue(mobile),
      ]);
      await c.read(gtfsRepositoryProvider.future);
      await c.read(settingsProvider.notifier).setSelectedStop('1150');
      c.listen(stopArrivalsProvider('1150'), (_, _) {}).close();
      await tester.pump(const Duration(seconds: 1));
      await c.read(settingsProvider.notifier).setSelectedStop('2000');
      await tester.pump(const Duration(seconds: 1));
      mobile.asked.clear();
      c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(mobile.asked, ['1150'], reason: 'no longer kept: fetched afresh');
      c.dispose();
    });

    testWidgets('watching your stop again refreshes it, keeping the old rows meanwhile', (tester) async {
      final mobile = _FakeMobile();
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
        metrobusMobileApiProvider.overrideWithValue(mobile),
      ]);
      await c.read(gtfsRepositoryProvider.future);
      await c.read(settingsProvider.notifier).setSelectedStop('1150');
      final first = c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(mobile.asked, hasLength(1));
      first.close();
      await tester.pump(const Duration(seconds: 30)); // its timer fires with nobody watching
      expect(mobile.asked, hasLength(1));
      final sub = c.listen(stopArrivalsProvider('1150'), (_, _) {});
      expect(sub.read().hasValue, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(mobile.asked.length, 2, reason: 'one refresh on coming back');
      c.dispose();
    });
  });

  group('stop arrivals and the app lifecycle', () {
    ProviderContainer containerWith(_FakeMobile mobile) {
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
        metrobusMobileApiProvider.overrideWithValue(mobile),
      ]);
      return c;
    }

    // Each test disposes its container itself: a pending provider timer would
    // otherwise outlive the test body.
    // testWidgets gives fake time: pump(Duration) fires the provider's timer.
    testWidgets('they keep polling while the app is in the foreground', (tester) async {
      final mobile = _FakeMobile();
      final c = containerWith(mobile);
      await c.read(gtfsRepositoryProvider.future);
      c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(mobile.asked, hasLength(1));
      await tester.pump(const Duration(seconds: 6));
      expect(mobile.asked.length, greaterThan(1));
      c.dispose();
    });

    testWidgets('a fetch slower than the poll interval still completes, and polling goes on after it', (tester) async {
      final mobile = _FakeMobile();
      final slow = _SlowTimeTrack(const Duration(seconds: 8)); // the default poll is 5 s
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        timetrackApiProvider.overrideWithValue(slow),
        metrobusMobileApiProvider.overrideWithValue(mobile),
      ]);
      await c.read(gtfsRepositoryProvider.future);
      c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 7));
      expect(c.read(stopArrivalsProvider('1150')).hasValue, isFalse, reason: 'still loading, not restarted');
      expect(slow.calls, 1, reason: 'the poll did not restart the fetch');
      await tester.pump(const Duration(seconds: 2));
      expect(c.read(stopArrivalsProvider('1150')).hasValue, isTrue);
      await tester.pump(const Duration(seconds: 6));
      expect(slow.calls, 2, reason: 'the next poll came one interval after the fetch ended');
      await tester.pump(const Duration(seconds: 7)); // let that second fetch end
      c.dispose();
    });

    testWidgets('they stop polling in the background and fetch once on return', (tester) async {
      final mobile = _FakeMobile();
      final c = containerWith(mobile);
      await c.read(gtfsRepositoryProvider.future);
      c.read(appForegroundProvider.notifier).setForeground(false);
      c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(mobile.asked, hasLength(1), reason: 'the first fetch still happens');

      await tester.pump(const Duration(seconds: 30));
      expect(mobile.asked, hasLength(1), reason: 'no timer re-fetch while backgrounded');

      c.read(appForegroundProvider.notifier).setForeground(true);
      await tester.pump(const Duration(seconds: 1));
      expect(mobile.asked, hasLength(2), reason: 'coming back fetches once');
      c.dispose();
    });

    testWidgets('going to the background does not itself fetch', (tester) async {
      final mobile = _FakeMobile();
      final c = containerWith(mobile);
      await c.read(gtfsRepositoryProvider.future);
      c.listen(stopArrivalsProvider('1150'), (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      c.read(appForegroundProvider.notifier).setForeground(false);
      await tester.pump(const Duration(seconds: 30));
      expect(mobile.asked, hasLength(1));
      c.dispose();
    });
  });
}

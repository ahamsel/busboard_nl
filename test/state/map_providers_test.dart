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

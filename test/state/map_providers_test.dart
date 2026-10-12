import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
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

  test('the sheet holds a stop or a bus, by value', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
    expect(c.read(homeSheetProvider), const StopSheet('1150'));
    c.read(homeSheetProvider.notifier).open(const BusSheet('2573'));
    expect(c.read(homeSheetProvider), const BusSheet('2573'));
    expect(const BusSheet('2573') == const BusSheet('2574'), isFalse);
    c.read(homeSheetProvider.notifier).home();
    expect(c.read(homeSheetProvider), const HomeSheetHome());
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

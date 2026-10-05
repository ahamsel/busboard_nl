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
}

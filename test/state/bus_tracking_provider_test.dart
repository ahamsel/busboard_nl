import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map/support/out_and_back.dart';

/// Riverpod pauses an async* provider that has no listener, so a bare
/// `read(provider.future)` never completes; hold a listener while waiting.
Future<Map<String, BusTrackingState>> firstSnapshot(ProviderContainer container) {
  container.listen(busTrackingStreamProvider, (_, _) {});
  return container.read(busTrackingStreamProvider.future);
}

/// Seconds since local midnight, a few seconds ago, as the feed reports it.
/// The store drops a fix whose clock is far from the fetch time, so a fixed
/// time of day would only pass for a few minutes a day.
int feedSeconds() {
  final now = DateTime.now();
  return (now.hour * 3600 + now.minute * 60 + now.second - 5).clamp(1, 86399);
}

class _FakeApi extends TimeTrackApi {
  _FakeApi(this.batches, {this.throwOnCalls = const {}});
  final List<List<TimeTrackVehicle>> batches;

  /// 1-based call numbers that throw instead of returning a result.
  final Set<int> throwOnCalls;
  var calls = 0;
  @override
  Future<TimeTrackFetchResult> fetchVehiclesResult() async {
    final call = ++calls;
    if (throwOnCalls.contains(call)) throw StateError('network down (call $call)');
    return TimeTrackFetchResult.success(batches[(call - 1).clamp(0, batches.length - 1)], source: LiveDataSource.gtfsRealtime);
  }
}

/// Settings that poll every second instead of the 5 s minimum the UI offers.
class _FastSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(refreshIntervalSeconds: 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the tracking stream publishes one snapshot per bus from the new store', () async {
    final api = _FakeApi([
      [fix(meters: 100, seconds: feedSeconds())],
    ]);
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => outAndBackRepo()),
      timetrackApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await container.read(gtfsRepositoryProvider.future);
    final snapshot = await firstSnapshot(container);
    final bus = snapshot['2573']!;
    expect(bus.vehicleId, '2573');
    expect(bus.routeNumber, 10);
    expect(bus.currentTripId, outAndBackTripId);
    expect(bus.shapeId, outAndBackShapeId);
    expect(bus.status, BusStatus.active);
    expect(bus.speedKmh, 29);
    expect(container.read(busTrackRendererProvider), isNotNull);
    expect(container.read(busTrackStoreProvider)!.tracks.keys, ['2573']);
  });

  test('with an empty schedule the stream is empty', () async {
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
      timetrackApiProvider.overrideWithValue(_FakeApi([[]])),
    ]);
    addTearDown(container.dispose);
    await container.read(gtfsRepositoryProvider.future);
    expect(await firstSnapshot(container), isEmpty);
  });

  test('while the schedule is still loading the stream is empty and there is no store', () async {
    final never = Completer<GtfsRepository>();
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) => never.future),
      timetrackApiProvider.overrideWithValue(_FakeApi([[]])),
    ]);
    addTearDown(container.dispose);
    expect(container.read(busTrackStoreProvider), isNull);
    expect(container.read(busTrackRendererProvider), isNull);
    expect(await firstSnapshot(container), isEmpty);
  });

  test('a poll that throws, even the first, does not break the stream; it recovers', () async {
    final api = _FakeApi([
      [fix(meters: 100, seconds: feedSeconds())],
    ], throwOnCalls: {1});
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => outAndBackRepo()),
      timetrackApiProvider.overrideWithValue(api),
      settingsProvider.overrideWith(_FastSettings.new),
    ]);
    addTearDown(container.dispose);
    await container.read(gtfsRepositoryProvider.future);

    final seen = <AsyncValue<Map<String, BusTrackingState>>>[];
    container.listen(busTrackingStreamProvider, (_, next) => seen.add(next), fireImmediately: true);
    final recovered = Completer<void>();
    container.listen(busTrackingStreamProvider, (_, next) {
      if (next.value?.containsKey('2573') ?? false) recovered.complete();
    });
    await recovered.future.timeout(const Duration(seconds: 10));

    expect(seen.any((v) => v.hasError), isFalse);
    expect(api.calls, greaterThanOrEqualTo(2));
    // The failed first poll still published a (empty) snapshot.
    expect(seen.firstWhere((v) => v.hasValue).value, isEmpty);
  });

  test('changing the refresh interval keeps the same store and renderer', () async {
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => outAndBackRepo()),
      timetrackApiProvider.overrideWithValue(_FakeApi([[]])),
    ]);
    addTearDown(container.dispose);
    await firstSnapshot(container);
    final store = container.read(busTrackStoreProvider);
    final renderer = container.read(busTrackRendererProvider);
    expect(store, isNotNull);
    expect(renderer, isNotNull);

    await container.read(settingsProvider.notifier).setRefreshInterval(30);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(settingsProvider).refreshIntervalSeconds, 30);
    expect(container.read(busTrackStoreProvider), same(store));
    expect(container.read(busTrackRendererProvider), same(renderer));
  });
}

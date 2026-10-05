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
  _FakeApi(this.batches);
  final List<List<TimeTrackVehicle>> batches;
  var calls = 0;
  @override
  Future<TimeTrackFetchResult> fetchVehiclesResult() async =>
      TimeTrackFetchResult.success(batches[(calls++).clamp(0, batches.length - 1)], source: LiveDataSource.gtfsRealtime);
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

  test('without a schedule the stream is empty', () async {
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
      timetrackApiProvider.overrideWithValue(_FakeApi([[]])),
    ]);
    addTearDown(container.dispose);
    await container.read(gtfsRepositoryProvider.future);
    expect(await firstSnapshot(container), isEmpty);
  });
}

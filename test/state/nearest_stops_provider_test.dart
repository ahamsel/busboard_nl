import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// A device whose location fix always fails, as when the user says
/// "No thanks" to Android's Location Accuracy dialog.
class _FailingGeolocator extends GeolocatorPlatform {
  int fixes = 0;

  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    fixes++;
    throw const LocationServiceDisabledException();
  }
}

/// A device at MUN Centre with location allowed.
class _FixedGeolocator extends GeolocatorPlatform {
  int fixes = 0;

  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    fixes++;
    return Position(
        latitude: 47.5733,
        longitude: -52.7329,
        timestamp: DateTime(2026, 10, 16),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
  }
}

void main() {
  test('a schedule that fails to reload keeps Near me on the one loaded, and the stop names with it', () async {
    final geo = GeolocatorPlatform.instance = _FixedGeolocator();
    var loads = 0;
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async {
        // Settings, Refresh schedule, while offline: the second load fails.
        if (++loads > 1) throw StateError('offline');
        return GtfsRepository()
          ..stopsById['1150'] = const StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.5733, stopLon: -52.7329);
      }),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(nearestStopsProvider, (_, _) {});
    addTearDown(sub.close);
    final info = container.listen(stopInfoProvider('1150'), (_, _) {});
    addTearDown(info.close);
    expect((await container.read(nearestStopsProvider.future)).single.stop.stopName, 'MUN Centre');
    expect(container.read(stopInfoProvider('1150'))?.stopName, 'MUN Centre');

    container.invalidate(gtfsRepositoryProvider);
    await expectLater(container.read(gtfsRepositoryProvider.future), throwsStateError, reason: 'the reload failed');
    expect((await container.read(nearestStopsProvider.future)).single.stop.stopName, 'MUN Centre',
        reason: 'Near me does not empty until a relaunch');
    expect(container.read(stopInfoProvider('1150'))?.stopName, 'MUN Centre',
        reason: 'the Board header keeps the name, not "Stop 1150"');
    expect(geo.fixes, 1, reason: 'the failed reload does not ask for the location again');
  });

  test('a failed location fix is not retried behind the user\'s back', () async {
    final geo = _FailingGeolocator();
    GeolocatorPlatform.instance = geo;
    final container = ProviderContainer(overrides: [gtfsRepositoryProvider.overrideWith((ref) => GtfsRepository())]);
    addTearDown(container.dispose);
    await container.read(gtfsRepositoryProvider.future);

    final sub = container.listen(nearestStopsProvider, (_, _) {});
    addTearDown(sub.close);
    // Riverpod's default retry would ask again after 200 ms, 400 ms, ...
    // and on Android each ask reopens the system dialog the user just declined.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(container.read(nearestStopsProvider).hasError, isTrue);
    expect(geo.fixes, 1);
  });
}

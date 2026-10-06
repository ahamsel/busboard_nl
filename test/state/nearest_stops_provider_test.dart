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

void main() {
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

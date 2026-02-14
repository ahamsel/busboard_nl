import 'package:flutter_test/flutter_test.dart';
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';

void main() {
  group('Nearest stop service', () {
    // Test stops around St. John's, NL
    final stops = [
      const StopInfo(
        stopId: '1001',
        stopName: 'Memorial University',
        stopLat: 47.5725,
        stopLon: -52.7336,
      ),
      const StopInfo(
        stopId: '1002',
        stopName: 'Avalon Mall',
        stopLat: 47.5645,
        stopLon: -52.7185,
      ),
      const StopInfo(
        stopId: '1003',
        stopName: 'Village Mall',
        stopLat: 47.5310,
        stopLon: -52.7895,
      ),
      const StopInfo(
        stopId: '1004',
        stopName: 'Close Stop', // very close to query point
        stopLat: 47.5727,
        stopLon: -52.7338,
      ),
      const StopInfo(
        stopId: '1005',
        stopName: 'Far Away Stop', // >50km away
        stopLat: 48.0000,
        stopLon: -53.0000,
      ),
    ];

    final service = NearestStopService();

    test('finds closest stops sorted by distance', () {
      final results = service.findNearestStops(
        latitude: 47.5726,
        longitude: -52.7337,
        allStops: stops,
        maxDistance: 5000, // 5km
        maxResults: 10,
      );

      // Should find at least Close Stop and Memorial University
      expect(results.isNotEmpty, true);

      // First result should be the closest one
      expect(results.first.stop.stopId, '1004'); // Close Stop

      // Results should be sorted by distance
      for (var i = 1; i < results.length; i++) {
        expect(
          results[i].distanceMeters >= results[i - 1].distanceMeters,
          true,
          reason: 'Results should be sorted by distance',
        );
      }
    });

    test('respects maxDistance filter', () {
      final results = service.findNearestStops(
        latitude: 47.5726,
        longitude: -52.7337,
        allStops: stops,
        maxDistance: 100, // 100m — very tight
        maxResults: 10,
      );

      // Should find only very close stops
      for (final r in results) {
        expect(r.distanceMeters <= 100, true);
      }
    });

    test('respects maxResults limit', () {
      final results = service.findNearestStops(
        latitude: 47.5726,
        longitude: -52.7337,
        allStops: stops,
        maxDistance: 50000, // 50km
        maxResults: 2,
      );

      expect(results.length, lessThanOrEqualTo(2));
    });

    test('excludes stops beyond maxDistance', () {
      final results = service.findNearestStops(
        latitude: 47.5726,
        longitude: -52.7337,
        allStops: stops,
        maxDistance: 800, // default 800m
        maxResults: 10,
      );

      // Far Away Stop should not be in results
      final farIds = results.map((r) => r.stop.stopId).toList();
      expect(farIds.contains('1005'), false);
    });

    test('distanceDisplay shows meters for <1km', () {
      final results = service.findNearestStops(
        latitude: 47.5726,
        longitude: -52.7337,
        allStops: stops,
        maxDistance: 500,
        maxResults: 10,
      );

      if (results.isNotEmpty) {
        // Should show in meters format
        expect(results.first.distanceDisplay.endsWith('m'), true);
      }
    });

    test('returns empty list when no stops nearby', () {
      final results = service.findNearestStops(
        latitude: 0.0, // middle of ocean
        longitude: 0.0,
        allStops: stops,
        maxDistance: 100,
        maxResults: 10,
      );

      expect(results.isEmpty, true);
    });
  });
}

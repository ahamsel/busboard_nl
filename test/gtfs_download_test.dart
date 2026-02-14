import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:busboard_nl/data/gtfs/gtfs_parser.dart';

/// Tests GTFS parsing against pre-downloaded data.
///
/// Uses the GTFS data at /tmp/gtfs_check (downloaded during investigation).
/// To regenerate: curl -o /tmp/metrobus_gtfs.zip https://www.metrobustransit.ca/google/google_transit.zip
///                && mkdir -p /tmp/gtfs_check && cd /tmp/gtfs_check && unzip -o /tmp/metrobus_gtfs.zip
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const gtfsDir = '/tmp/gtfs_check';

  group('GTFS Parsing', () {
    test('stops.txt parses correctly and contains stop 2735', () async {
      final dir = Directory(gtfsDir);
      if (!dir.existsSync()) {
        markTestSkipped('GTFS data not available at $gtfsDir');
        return;
      }

      final parser = GtfsParser(gtfsDir);
      final stops = await parser.parseStops();

      expect(stops, isNotEmpty);
      expect(stops.length, greaterThan(100));

      final stop2735 = stops.where((s) => s.stopId == '2735').toList();
      expect(stop2735, hasLength(1));
      expect(stop2735.first.stopName, contains('Gower'));
      expect(stop2735.first.stopLat, closeTo(47.565, 0.01));
      expect(stop2735.first.stopLon, closeTo(-52.709, 0.01));
    });

    test('stop_times.txt has entries for stop 2735', () async {
      final dir = Directory(gtfsDir);
      if (!dir.existsSync()) {
        markTestSkipped('GTFS data not available at $gtfsDir');
        return;
      }

      final parser = GtfsParser(gtfsDir);
      final stopTimes = await parser.parseStopTimes();

      expect(stopTimes, isNotEmpty);

      final times2735 = stopTimes.where((st) => st.stopId == '2735').toList();
      expect(times2735, isNotEmpty);
      // Verify departure times parse (have colons, not empty)
      for (final st in times2735) {
        expect(st.departureTime, contains(':'));
        expect(st.tripId, isNotEmpty);
      }
    });

    test('routes and trips parse correctly', () async {
      final dir = Directory(gtfsDir);
      if (!dir.existsSync()) {
        markTestSkipped('GTFS data not available at $gtfsDir');
        return;
      }

      final parser = GtfsParser(gtfsDir);
      final routes = await parser.parseRoutes();
      final trips = await parser.parseTrips();
      final calendars = await parser.parseCalendar();

      expect(routes, isNotEmpty);
      expect(trips, isNotEmpty);
      expect(calendars, isNotEmpty);

      // Verify route 10 exists (which serves stop 2735)
      final route10 = routes.where((r) => r.routeShortName == '10').toList();
      expect(route10, isNotEmpty);
    });
  });
}

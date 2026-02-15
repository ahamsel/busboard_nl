import 'dart:math';
import 'gtfs_models.dart';
import 'gtfs_parser.dart';
import 'gtfs_downloader.dart';

/// In-memory repository of GTFS data with fast lookup indexes.
///
/// Loads data from cached/downloaded GTFS files and builds
/// maps for O(1) lookups by stop, route, trip, and service.
class GtfsRepository {
  final Map<String, StopInfo> stopsById = {};
  final Map<String, RouteInfo> routesById = {};
  final Map<String, TripInfo> tripsById = {};
  final Map<String, List<StopTimeRow>> stopTimesByStopId = {};
  final Map<String, ServiceCalendar> calendarsById = {};
  final List<CalendarDate> calendarDates = [];
  final Map<String, List<ShapePoint>> shapesById = {};
  final Map<String, List<double>> shapeCumulativeDistances = {};
  final Map<String, List<TripShapeEntry>> tripsByRouteShortName = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  final GtfsDownloader _downloader = GtfsDownloader();

  /// Load GTFS data: download if needed, parse, and build indexes.
  ///
  /// Set [force] to true to re-download even if cache is valid.
  Future<void> load({bool force = false}) async {
    final dirPath = await _downloader.downloadAndExtract(force: force);
    final parser = GtfsParser(dirPath);

    // Parse all files
    final stops = await parser.parseStops();
    final routes = await parser.parseRoutes();
    final trips = await parser.parseTrips();
    final stopTimes = await parser.parseStopTimes();
    final calendars = await parser.parseCalendar();
    final calDates = await parser.parseCalendarDates();
    final shapes = await parser.parseShapes();

    // Build indexes
    stopsById.clear();
    for (final stop in stops) {
      stopsById[stop.stopId] = stop;
    }

    routesById.clear();
    for (final route in routes) {
      routesById[route.routeId] = route;
    }

    tripsById.clear();
    for (final trip in trips) {
      tripsById[trip.tripId] = trip;
    }

    stopTimesByStopId.clear();
    for (final st in stopTimes) {
      stopTimesByStopId.putIfAbsent(st.stopId, () => []).add(st);
    }

    calendarsById.clear();
    for (final cal in calendars) {
      calendarsById[cal.serviceId] = cal;
    }

    calendarDates.clear();
    calendarDates.addAll(calDates);

    // Build shapes index (sorted by sequence)
    shapesById.clear();
    for (final sp in shapes) {
      shapesById.putIfAbsent(sp.shapeId, () => []).add(sp);
    }
    for (final points in shapesById.values) {
      points.sort((a, b) => a.sequence.compareTo(b.sequence));
    }

    // Precompute cumulative haversine distances per shape
    shapeCumulativeDistances.clear();
    for (final entry in shapesById.entries) {
      final points = entry.value;
      final cumDist = <double>[0.0];
      for (var i = 1; i < points.length; i++) {
        final d = _haversineDistance(
          points[i - 1].lat,
          points[i - 1].lon,
          points[i].lat,
          points[i].lon,
        );
        cumDist.add(cumDist.last + d);
      }
      shapeCumulativeDistances[entry.key] = cumDist;
    }

    // Build route short name → trip/shape lookup for fallback matching
    tripsByRouteShortName.clear();
    for (final trip in trips) {
      if (trip.shapeId == null || trip.shapeId!.isEmpty) continue;
      final route = routesById[trip.routeId];
      if (route == null) continue;
      tripsByRouteShortName.putIfAbsent(route.routeShortName, () => []).add(
        TripShapeEntry(
          tripId: trip.tripId,
          shapeId: trip.shapeId!,
          headsign: trip.tripHeadsign,
          directionId: trip.directionId,
          serviceId: trip.serviceId,
        ),
      );
    }

    _loaded = true;
  }

  /// Check if the GTFS cache is still valid.
  Future<bool> isCacheValid() => _downloader.isCacheValid();

  /// Get last download time.
  Future<DateTime?> lastDownloadTime() => _downloader.lastDownloadTime();

  /// Check if a service runs on a given date, accounting for
  /// both calendar.txt and calendar_dates.txt.
  bool isServiceActiveOn(String serviceId, DateTime date) {
    // Check calendar_dates exceptions first
    final dateOnly = DateTime(date.year, date.month, date.day);
    for (final cd in calendarDates) {
      if (cd.serviceId == serviceId) {
        final cdDate = DateTime(cd.date.year, cd.date.month, cd.date.day);
        if (cdDate == dateOnly) {
          return cd.exceptionType == ExceptionType.added;
        }
      }
    }

    // Fall back to regular calendar
    final calendar = calendarsById[serviceId];
    if (calendar == null) return false;
    return calendar.runsOn(dateOnly);
  }

  /// Get all active service IDs for a given date.
  Set<String> activeServiceIds(DateTime date) {
    final active = <String>{};
    final dateOnly = DateTime(date.year, date.month, date.day);

    // Start with regular calendars
    for (final cal in calendarsById.values) {
      if (cal.runsOn(dateOnly)) {
        active.add(cal.serviceId);
      }
    }

    // Apply exceptions
    for (final cd in calendarDates) {
      final cdDate = DateTime(cd.date.year, cd.date.month, cd.date.day);
      if (cdDate == dateOnly) {
        if (cd.exceptionType == ExceptionType.added) {
          active.add(cd.serviceId);
        } else {
          active.remove(cd.serviceId);
        }
      }
    }

    return active;
  }

  static const _earthRadiusMeters = 6371000.0;

  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}

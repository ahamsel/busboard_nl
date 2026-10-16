import 'dart:math';
import 'gtfs_models.dart';
import 'gtfs_parser.dart';
import 'gtfs_time.dart';
import 'gtfs_downloader.dart';
import 'headsign.dart';

/// In-memory repository of GTFS data with fast lookup indexes.
///
/// Loads data from cached/downloaded GTFS files and builds
/// maps for O(1) lookups by stop, route, trip, and service.
class GtfsRepository {
  final Map<String, StopInfo> stopsById = {};
  final Map<String, RouteInfo> routesById = {};
  final Map<String, TripInfo> tripsById = {};
  final Map<String, List<StopTimeRow>> stopTimesByStopId = {};

  final Map<String, List<String>> _routesForStopCache = {};

  /// Route short names serving [stopId], sorted with [compareRouteNames].
  /// Memoised; cleared whenever data is (re)loaded.
  List<String> routeShortNamesForStop(String stopId) {
    final cached = _routesForStopCache[stopId];
    if (cached != null) return cached;
    final names = <String>{};
    for (final row in stopTimesByStopId[stopId] ?? const <StopTimeRow>[]) {
      final trip = tripsById[row.tripId];
      if (trip == null) continue;
      final route = routesById[trip.routeId];
      if (route == null) continue;
      names.add(route.routeShortName);
    }
    final sorted = names.toList()..sort(compareRouteNames);
    return _routesForStopCache[stopId] = List.unmodifiable(sorted);
  }

  final Map<String, List<RouteDirections>> _directionsForStopCache = {};
  final Map<(String, int), List<int>> _departuresCache = {};

  /// The seconds after [day]'s midnight at which a bus on a service running that day leaves [stopId], sorted (past
  /// 86400 for a trip that runs on after midnight). Empty when no service runs that day. Memoised per stop and
  /// date, so a screen that asks on every rebuild scans the stop's times once; cleared whenever data is (re)loaded.
  List<int> departureSecondsOn(String stopId, DateTime day) {
    final key = (stopId, day.year * 10000 + day.month * 100 + day.day);
    final cached = _departuresCache[key];
    if (cached != null) return cached;
    // A week of stops and days is a few hundred entries; a long-running app that crosses many days starts over.
    if (_departuresCache.length > 2000) _departuresCache.clear();
    final services = activeServiceIds(day);
    final seconds = <int>[];
    if (services.isNotEmpty) {
      for (final st in stopTimesByStopId[stopId] ?? const <StopTimeRow>[]) {
        final trip = tripsById[st.tripId];
        if (trip == null || !services.contains(trip.serviceId)) continue;
        try {
          seconds.add(GtfsTime.parse(st.departureTime).totalSeconds);
        } on FormatException {
          continue;
        }
      }
      seconds.sort();
    }
    return _departuresCache[key] = List.unmodifiable(seconds);
  }
  Map<String, int>? _lastSequenceByTrip;

  /// Each route serving [stopId] (in [routeShortNamesForStop] order) with
  /// where its buses go from here: the [headsignDestination] of trips that
  /// leave this stop, at most two, most frequent first (ties alphabetical).
  /// Trips that end here are skipped. Memoised; cleared whenever data is
  /// (re)loaded.
  List<RouteDirections> routeDirectionsForStop(String stopId) {
    final cached = _directionsForStopCache[stopId];
    if (cached != null) return cached;
    final lastSequence = _lastSequenceByTrip ??= _buildLastSequenceByTrip();
    final counts = <String, Map<String, int>>{};
    for (final row in stopTimesByStopId[stopId] ?? const <StopTimeRow>[]) {
      final trip = tripsById[row.tripId];
      if (trip == null) continue;
      final route = routesById[trip.routeId];
      if (route == null) continue;
      if (row.stopSequence >= (lastSequence[row.tripId] ?? 0)) continue;
      final destination = headsignDestination(trip.tripHeadsign);
      if (destination.isEmpty) continue;
      final byDestination = counts.putIfAbsent(route.routeShortName, () => {});
      byDestination[destination] = (byDestination[destination] ?? 0) + 1;
    }
    final directions = [
      for (final name in routeShortNamesForStop(stopId))
        RouteDirections(
          routeShortName: name,
          destinations: List.unmodifiable(
            ((counts[name] ?? const <String, int>{}).entries.toList()
                  ..sort((a, b) => a.value != b.value ? b.value - a.value : a.key.compareTo(b.key)))
                .take(2)
                .map((e) => e.key),
          ),
        ),
    ];
    return _directionsForStopCache[stopId] = List.unmodifiable(directions);
  }

  Map<String, int> _buildLastSequenceByTrip() {
    final last = <String, int>{};
    for (final rows in stopTimesByStopId.values) {
      for (final row in rows) {
        final seen = last[row.tripId];
        if (seen == null || row.stopSequence > seen) last[row.tripId] = row.stopSequence;
      }
    }
    return last;
  }

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  /// The numeric value of a digit-only name, or null when [s] is not
  /// digit-only or does not fit an int (treated as non-numeric).
  static int? _numericValue(String s) =>
      _digitsOnly.hasMatch(s) ? int.tryParse(s) : null;

  /// Digit-only route ids first (numeric order, ties broken by string order),
  /// then the rest alphabetically. A strict total order: 0 only when equal.
  static int compareRouteNames(String a, String b) {
    final ai = _numericValue(a);
    final bi = _numericValue(b);
    if (ai != null && bi != null) {
      final c = ai.compareTo(bi);
      return c != 0 ? c : a.compareTo(b);
    }
    if (ai != null) return -1;
    if (bi != null) return 1;
    return a.compareTo(b);
  }
  final Map<String, ServiceCalendar> calendarsById = {};
  final List<CalendarDate> calendarDates = [];

  /// transfers.txt rules, by from stop.
  final Map<String, List<TransferRule>> transfersByFromStop = {};
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
    await loadFromDirectory(dirPath);
  }

  /// Forgets everything worked out from the data (route names and directions per stop, departures per service day):
  /// it is called when the data is loaded again.
  void clearDerivedCaches() {
    _routesForStopCache.clear();
    _directionsForStopCache.clear();
    _departuresCache.clear();
    _lastSequenceByTrip = null;
  }

  /// Load already-extracted GTFS files from [dirPath].
  ///
  /// This keeps production loading and diagnostic replay on the same parser
  /// and indexes without forcing a network download or platform cache lookup.
  Future<void> loadFromDirectory(String dirPath) async {
    clearDerivedCaches();
    final parser = GtfsParser(dirPath);

    // Parse all files
    final stops = await parser.parseStops();
    final routes = await parser.parseRoutes();
    final trips = await parser.parseTrips();
    final stopTimes = await parser.parseStopTimes();
    final calendars = await parser.parseCalendar();
    final calDates = await parser.parseCalendarDates();
    final shapes = await parser.parseShapes();
    final transfers = await parser.parseTransfers();

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
    // Built here rather than on the picker's first frame.
    _lastSequenceByTrip = _buildLastSequenceByTrip();

    calendarsById.clear();
    for (final cal in calendars) {
      calendarsById[cal.serviceId] = cal;
    }

    calendarDates.clear();
    calendarDates.addAll(calDates);

    transfersByFromStop.clear();
    for (final t in transfers) {
      transfersByFromStop.putIfAbsent(t.fromStopId, () => []).add(t);
    }

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
      tripsByRouteShortName
          .putIfAbsent(route.routeShortName, () => [])
          .add(
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

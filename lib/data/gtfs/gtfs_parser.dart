import 'dart:io';
import 'package:csv/csv.dart';
import 'gtfs_models.dart';

/// Parses GTFS CSV files from an extracted GTFS directory.
class GtfsParser {
  final String directoryPath;

  GtfsParser(this.directoryPath);

  /// Read and parse a CSV file, returning rows as maps.
  Future<List<Map<String, String>>> _parseCsv(String filename) async {
    final file = File('$directoryPath/$filename');
    if (!await file.exists()) {
      return [];
    }

    final content = await file.readAsString();
    final rows = const CsvDecoder().convert(content);

    if (rows.isEmpty) return [];

    // First row is headers
    final headers = rows.first.map((e) => e.toString().trim()).toList();
    final result = <Map<String, String>>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final map = <String, String>{};
      for (var j = 0; j < headers.length && j < row.length; j++) {
        map[headers[j]] = row[j].toString().trim();
      }
      result.add(map);
    }

    return result;
  }

  // Parse stops.txt into StopInfo list.
  Future<List<StopInfo>> parseStops() async {
    final rows = await _parseCsv('stops.txt');
    return rows
        .map((row) {
          return StopInfo(
            stopId: row['stop_id'] ?? '',
            stopName: row['stop_name'] ?? '',
            stopLat: double.tryParse(row['stop_lat'] ?? '') ?? 0.0,
            stopLon: double.tryParse(row['stop_lon'] ?? '') ?? 0.0,
          );
        })
        .where((s) => s.stopId.isNotEmpty)
        .toList();
  }

  // Parse routes.txt into RouteInfo list.
  Future<List<RouteInfo>> parseRoutes() async {
    final rows = await _parseCsv('routes.txt');
    return rows
        .map((row) {
          return RouteInfo(
            routeId: row['route_id'] ?? '',
            routeShortName: row['route_short_name'] ?? '',
            routeLongName: row['route_long_name'] ?? '',
          );
        })
        .where((r) => r.routeId.isNotEmpty)
        .toList();
  }

  // Parse trips.txt into TripInfo list.
  Future<List<TripInfo>> parseTrips() async {
    final rows = await _parseCsv('trips.txt');
    return rows
        .map((row) {
          return TripInfo(
            tripId: row['trip_id'] ?? '',
            routeId: row['route_id'] ?? '',
            serviceId: row['service_id'] ?? '',
            tripHeadsign: row['trip_headsign'] ?? '',
            directionId: int.tryParse(row['direction_id'] ?? '') ?? 0,
          );
        })
        .where((t) => t.tripId.isNotEmpty)
        .toList();
  }

  // Parse stop_times.txt into StopTimeRow list.
  Future<List<StopTimeRow>> parseStopTimes() async {
    final rows = await _parseCsv('stop_times.txt');
    return rows
        .map((row) {
          return StopTimeRow(
            tripId: row['trip_id'] ?? '',
            arrivalTime: row['arrival_time'] ?? '',
            departureTime: row['departure_time'] ?? '',
            stopId: row['stop_id'] ?? '',
            stopSequence: int.tryParse(row['stop_sequence'] ?? '') ?? 0,
          );
        })
        .where((st) => st.tripId.isNotEmpty)
        .toList();
  }

  // Parse calendar.txt into ServiceCalendar list.
  Future<List<ServiceCalendar>> parseCalendar() async {
    final rows = await _parseCsv('calendar.txt');
    return rows
        .map((row) {
          return ServiceCalendar(
            serviceId: row['service_id'] ?? '',
            monday: row['monday'] == '1',
            tuesday: row['tuesday'] == '1',
            wednesday: row['wednesday'] == '1',
            thursday: row['thursday'] == '1',
            friday: row['friday'] == '1',
            saturday: row['saturday'] == '1',
            sunday: row['sunday'] == '1',
            startDate: _parseDate(row['start_date'] ?? ''),
            endDate: _parseDate(row['end_date'] ?? ''),
          );
        })
        .where((c) => c.serviceId.isNotEmpty)
        .toList();
  }

  // Parse calendar_dates.txt into CalendarDate list.
  Future<List<CalendarDate>> parseCalendarDates() async {
    final rows = await _parseCsv('calendar_dates.txt');
    return rows
        .map((row) {
          final exType = row['exception_type'] == '1'
              ? ExceptionType.added
              : ExceptionType.removed;
          return CalendarDate(
            serviceId: row['service_id'] ?? '',
            date: _parseDate(row['date'] ?? ''),
            exceptionType: exType,
          );
        })
        .where((cd) => cd.serviceId.isNotEmpty)
        .toList();
  }

  /// Parse GTFS date format: YYYYMMDD → DateTime.
  static DateTime _parseDate(String dateStr) {
    if (dateStr.length != 8) return DateTime(2000);
    final year = int.parse(dateStr.substring(0, 4));
    final month = int.parse(dateStr.substring(4, 6));
    final day = int.parse(dateStr.substring(6, 8));
    return DateTime(year, month, day);
  }
}

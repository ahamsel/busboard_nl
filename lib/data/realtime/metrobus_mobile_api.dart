import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/gtfs/gtfs_time.dart';

/// A single departure row scraped from metrobusmobile.com.
class MetrobusDeparture {
  /// Route-run identifier (e.g. "14-1").
  final String routeRun;

  /// Route short name extracted from routeRun (e.g. "14").
  final String routeShortName;

  /// Vehicle number (e.g. "1417").
  final String vehicle;

  /// Scheduled time string as shown on the page (e.g. "1:55p").
  final String scheduledTime;

  /// Predicted time string as shown on the page (e.g. "1:57p").
  final String predictedTime;

  /// Destination headsign (e.g. "MI - Eastern Health").
  final String headsign;

  /// Current location text (e.g. "Ridge Rd near Ecole").
  final String currentLocation;

  /// Whether the vehicle is actively tracked.
  final bool isTracked;

  const MetrobusDeparture({
    required this.routeRun,
    required this.routeShortName,
    required this.vehicle,
    required this.scheduledTime,
    required this.predictedTime,
    required this.headsign,
    required this.currentLocation,
    required this.isTracked,
  });

  /// Parse a time string like "1:55p" or "12:30a" into a [GtfsTime].
  ///
  /// Returns null if the format is unrecognised.
  static GtfsTime? parseTimeToGtfs(String timeStr) {
    // Match patterns like "1:55p", "12:30a", "1:55 PM", "12:30 AM"
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*([aApP][mM]?)$',
    ).firstMatch(timeStr.trim());
    if (match == null) return null;

    var hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final ampm = match.group(3)!.toLowerCase();

    if (ampm.startsWith('p') && hours != 12) {
      hours += 12;
    } else if (ampm.startsWith('a') && hours == 12) {
      hours = 0;
    }

    return GtfsTime.fromSeconds(hours * 3600 + minutes * 60);
  }

  @override
  String toString() =>
      'MetrobusDeparture($routeRun, vehicle=$vehicle, '
      'sched=$scheduledTime, pred=$predictedTime, '
      'headsign=$headsign, tracked=$isTracked)';
}

/// HTTP client for scraping predicted departures from metrobusmobile.com.
///
/// This is the "edgy mode" data source — uses web scraping rather than
/// an official API. Provides agency-predicted per-stop departure times
/// that account for dwell time, signal delays, and dispatch overrides.
class MetrobusMobileApi {
  static const _baseUrl = 'https://www.metrobusmobile.com/departures/';

  final http.Client _client;

  MetrobusMobileApi({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch predicted departures for [stopId] from metrobusmobile.com.
  ///
  /// Returns empty list on any error (graceful degradation).
  Future<List<MetrobusDeparture>> fetchDepartures(String stopId) async {
    try {
      final encoded = base64Encode(utf8.encode(stopId));
      final url = '$_baseUrl?s=$encoded';

      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            '[MetrobusMobile] HTTP ${response.statusCode} for stop $stopId',
          );
        }
        return [];
      }

      return _parseHtml(response.body);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MetrobusMobile] Error fetching stop $stopId: $e');
      }
      return [];
    }
  }

  /// Parse the HTML response into departure rows.
  ///
  /// The page contains a table with rows like:
  /// <tr><td>14-1</td><td>1417</td><td>1:55p</td><td>1:57p</td>
  ///     <td>MI - Eastern Health</td><td>Ridge Rd near Ecole</td></tr>
  List<MetrobusDeparture> _parseHtml(String html) {
    final departures = <MetrobusDeparture>[];

    // Match table rows with 6 cells (route, vehicle, due, predicted, dest, location)
    // The HTML structure uses <td> cells within <tr> rows.
    final rowPattern = RegExp(
      r'<tr[^>]*>\s*'
      r'<td[^>]*>(.*?)</td>\s*'
      r'<td[^>]*>(.*?)</td>\s*'
      r'<td[^>]*>(.*?)</td>\s*'
      r'<td[^>]*>(.*?)</td>\s*'
      r'<td[^>]*>(.*?)</td>\s*'
      r'<td[^>]*>(.*?)</td>\s*'
      r'</tr>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in rowPattern.allMatches(html)) {
      final routeRun = _stripHtml(match.group(1) ?? '').trim();
      final vehicle = _stripHtml(match.group(2) ?? '').trim();
      final due = _stripHtml(match.group(3) ?? '').trim();
      final predicted = _stripHtml(match.group(4) ?? '').trim();
      final destination = _stripHtml(match.group(5) ?? '').trim();
      final location = _stripHtml(match.group(6) ?? '').trim();

      // Skip header rows or empty rows
      if (routeRun.isEmpty ||
          due.isEmpty ||
          routeRun.toLowerCase() == 'route') {
        continue;
      }

      // Extract route short name from route-run (e.g. "14-1" → "14")
      final dashIdx = routeRun.indexOf('-');
      final routeShortName =
          dashIdx > 0 ? routeRun.substring(0, dashIdx) : routeRun;

      // Determine tracking status from location text
      final isTracked = location.isNotEmpty &&
          !location.toLowerCase().contains('waiting to track');

      departures.add(
        MetrobusDeparture(
          routeRun: routeRun,
          routeShortName: routeShortName,
          vehicle: vehicle,
          scheduledTime: due,
          predictedTime: predicted.isNotEmpty ? predicted : due,
          headsign: destination,
          currentLocation: location,
          isTracked: isTracked,
        ),
      );
    }

    if (kDebugMode && departures.isNotEmpty) {
      debugPrint(
        '[MetrobusMobile] Parsed ${departures.length} departures',
      );
    }

    return departures;
  }

  /// Strip HTML tags from a string.
  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  void dispose() {
    _client.close();
  }
}

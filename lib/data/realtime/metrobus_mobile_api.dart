import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/gtfs/gtfs_time.dart';

enum MetrobusDepartureSource { timeTrackJson }

/// The result of one stop-specific Metrobus departure request.
class MetrobusDeparturesResult {
  final List<MetrobusDeparture> departures;
  final bool succeeded;
  final bool realtimeAvailable;
  final bool serviceOperating;
  final String? message;
  final MetrobusDepartureSource? source;
  final DateTime fetchedAt;

  const MetrobusDeparturesResult({
    required this.departures,
    required this.succeeded,
    required this.realtimeAvailable,
    required this.serviceOperating,
    required this.fetchedAt,
    this.message,
    this.source,
  });

  factory MetrobusDeparturesResult.failure() => MetrobusDeparturesResult(
    departures: const [],
    succeeded: false,
    realtimeAvailable: false,
    serviceOperating: true,
    fetchedAt: DateTime.now(),
  );
}

/// A single stop departure reported by Metrobus Mobile.
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

  /// Exact GTFS trip ID when supplied by the JSON endpoint.
  final String tripId;

  /// Service-day seconds supplied by Metrobus.
  final int? scheduledDepartureSeconds;
  final int? predictedDepartureSeconds;

  /// Countdown at the time the endpoint generated this row.
  final int? secondsToDeparture;

  /// Positive values mean the departure is running late.
  final int? delaySeconds;

  /// The endpoint's explicit realtime flag. This is deliberately not inferred
  /// from the presence of a vehicle number.
  final bool isRealtime;

  final String predictionSource;
  final String confidenceLabel;
  final DateTime? updatedAt;

  const MetrobusDeparture({
    required this.routeRun,
    required this.routeShortName,
    required this.vehicle,
    required this.scheduledTime,
    required this.predictedTime,
    required this.headsign,
    required this.currentLocation,
    required this.isTracked,
    this.tripId = '',
    this.scheduledDepartureSeconds,
    this.predictedDepartureSeconds,
    this.secondsToDeparture,
    this.delaySeconds,
    this.isRealtime = false,
    this.predictionSource = '',
    this.confidenceLabel = '',
    this.updatedAt,
  });

  /// Parse a time string like "1:55p" or "12:30a" into a [GtfsTime].
  ///
  /// Returns null if the format is unrecognised.
  static GtfsTime? parseTimeToGtfs(String timeStr) {
    final twentyFourHour = RegExp(
      r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$',
    ).firstMatch(timeStr.trim());
    if (twentyFourHour != null) {
      final hours = int.parse(twentyFourHour.group(1)!);
      final minutes = int.parse(twentyFourHour.group(2)!);
      final seconds = int.tryParse(twentyFourHour.group(3) ?? '') ?? 0;
      return GtfsTime.fromSeconds(hours * 3600 + minutes * 60 + seconds);
    }

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

  GtfsTime? get scheduledGtfsTime => scheduledDepartureSeconds == null
      ? parseTimeToGtfs(scheduledTime)
      : GtfsTime.fromSeconds(scheduledDepartureSeconds!);

  GtfsTime? get predictedGtfsTime => predictedDepartureSeconds == null
      ? parseTimeToGtfs(predictedTime)
      : GtfsTime.fromSeconds(predictedDepartureSeconds!);

  @override
  String toString() =>
      'MetrobusDeparture($routeRun, vehicle=$vehicle, '
      'sched=$scheduledTime, pred=$predictedTime, '
      'headsign=$headsign, realtime=$isRealtime)';
}

class _CachedDepartures {
  final MetrobusDeparturesResult result;
  final DateTime storedAt;

  const _CachedDepartures(this.result, this.storedAt);
}

/// HTTP client for Metrobus's stop-specific prediction service.
///
/// Uses the structured JSON endpoint that drives Metrobus's own kiosk/SMS
/// link. This client deliberately does not scrape the legacy HTML pages.
class MetrobusMobileApi {
  static const _kioskApiUrl =
      'https://www.metrobusmobile.com/NextBus/fleetview.asp';
  static const _cacheDuration = Duration(seconds: 18);

  final http.Client _client;
  final Map<String, _CachedDepartures> _cache = {};

  MetrobusMobileApi({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch predicted departures for [stopId] from metrobusmobile.com.
  ///
  /// Returns empty list on any error (graceful degradation).
  Future<List<MetrobusDeparture>> fetchDepartures(String stopId) async {
    return (await fetchDeparturesResult(stopId)).departures;
  }

  /// Fetches the same JSON that drives Metrobus's mobile kiosk.
  ///
  /// Successful responses are cached just under the kiosk's own 20-second
  /// refresh period so a five-second board refresh does not hammer the source.
  Future<MetrobusDeparturesResult> fetchDeparturesResult(
    String stopId, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final cached = _cache[stopId];
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.storedAt) < _cacheDuration) {
      return cached.result;
    }

    final jsonResult = await _fetchKioskJson(stopId);
    if (jsonResult != null) {
      _cache[stopId] = _CachedDepartures(jsonResult, now);
      return jsonResult;
    }
    return MetrobusDeparturesResult.failure();
  }

  Future<MetrobusDeparturesResult?> _fetchKioskJson(String stopId) async {
    try {
      final url = Uri.parse(_kioskApiUrl).replace(
        queryParameters: {
          'type': 'timetrackjson',
          'stopid': stopId,
          'lookaheadMinutes': '120',
        },
      );

      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            '[MetrobusMobile] Kiosk HTTP ${response.statusCode} '
            'for stop $stopId',
          );
        }
        return null;
      }

      return _parseKioskJson(response.body);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MetrobusMobile] Kiosk error for stop $stopId: $e');
      }
      return null;
    }
  }

  MetrobusDeparturesResult? _parseKioskJson(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }

    final List<Object?> rows;
    bool realtimeAvailable = true;
    bool serviceOperating = true;
    String? message;
    if (decoded is List) {
      rows = decoded.cast<Object?>();
    } else if (decoded is Map<String, dynamic>) {
      final rawRows = decoded['arrivals'];
      if (rawRows != null && rawRows is! List) return null;
      rows = (rawRows as List?)?.cast<Object?>() ?? const [];
      realtimeAvailable = _asBool(decoded['realtimeAvailable']) ?? true;
      serviceOperating = _asBool(decoded['serviceOperating']) ?? true;
      message = _asString(decoded['message']);
    } else {
      return null;
    }

    final departures = rows
        .whereType<Map>()
        .map((row) => _parseKioskDeparture(row.cast<String, dynamic>()))
        .whereType<MetrobusDeparture>()
        .toList(growable: false);

    return MetrobusDeparturesResult(
      departures: departures,
      succeeded: true,
      realtimeAvailable:
          realtimeAvailable &&
          departures.any((departure) => departure.isRealtime),
      serviceOperating: serviceOperating,
      message: message,
      source: MetrobusDepartureSource.timeTrackJson,
      fetchedAt: DateTime.now(),
    );
  }

  MetrobusDeparture? _parseKioskDeparture(Map<String, dynamic> row) {
    final route = _asString(row['route']);
    if (route == null || route.isEmpty) return null;

    final scheduledSeconds = _asInt(
      row['scheduledDepartureSeconds'] ?? row['departureTimeSeconds'],
    );
    final scheduledText = scheduledSeconds == null
        ? ''
        : _formatSecondsAsTime(scheduledSeconds);
    if (scheduledText.isEmpty) return null;

    final predictedSeconds = _asInt(row['predictedDepartureSeconds']);
    final displayTime = _asString(row['displayTime']);
    final displayTimeIsClock =
        displayTime != null &&
        MetrobusDeparture.parseTimeToGtfs(displayTime) != null;
    final predictedText = predictedSeconds != null
        ? _formatSecondsAsTime(predictedSeconds)
        : displayTimeIsClock
        ? displayTime
        : scheduledText;

    final source = (_asString(row['predictionSource']) ?? '').toLowerCase();
    final explicitRealtime = _asBool(row['isRealtime']);
    final isRealtime = explicitRealtime ?? source == 'realtime';
    final run =
        _asString(row['runNumber'] ?? row['block'] ?? row['current_route']) ??
        route;
    final routeNumber = int.tryParse(route)?.toString() ?? route;

    return MetrobusDeparture(
      routeRun: run,
      routeShortName: routeNumber,
      vehicle: _normaliseVehicle(_asString(row['vehicle']) ?? ''),
      scheduledTime: scheduledText,
      predictedTime: predictedText,
      headsign:
          _asString(
            row['direction'] ??
                row['trip_headsign'] ??
                row['headsign'] ??
                row['destination'],
          ) ??
          '',
      currentLocation:
          _asString(
            row['currentLocation'] ??
                row['currentLocationStopName'] ??
                row['nearestStopName'],
          ) ??
          '',
      isTracked: isRealtime,
      tripId: _asString(row['tripId'] ?? row['trip_id']) ?? '',
      scheduledDepartureSeconds: scheduledSeconds,
      predictedDepartureSeconds: predictedSeconds,
      secondsToDeparture: _asInt(row['secondsToDeparture']),
      delaySeconds: _asInt(row['delaySeconds']),
      isRealtime: isRealtime,
      predictionSource: source,
      confidenceLabel:
          _asString(row['confidenceLabel'] ?? row['confidence_label']) ?? '',
      updatedAt: DateTime.tryParse(_asString(row['updatedAt']) ?? ''),
    );
  }

  static String _formatSecondsAsTime(int totalSeconds) {
    final seconds = totalSeconds % 86400;
    final hour24 = seconds ~/ 3600;
    final minute = (seconds % 3600) ~/ 60;
    final suffix = hour24 >= 12 ? 'p' : 'a';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')}$suffix';
  }

  static String _normaliseVehicle(String value) {
    final clean = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(clean)) return clean;
    return int.tryParse(clean)?.toString() ?? clean;
  }

  static String? _asString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool? _asBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return null;
  }

  void dispose() {
    _client.close();
  }
}

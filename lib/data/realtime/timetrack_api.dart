import 'dart:convert';
import 'dart:developer' as developer;

import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;

import 'timetrack_models.dart';

enum LiveDataSource {
  gtfsRealtime,
  fleetView,
  legacyTimeTrack;

  String get label => switch (this) {
    LiveDataSource.gtfsRealtime => 'GTFS-Realtime',
    LiveDataSource.fleetView => 'Metrobus Fleet View',
    LiveDataSource.legacyTimeTrack => 'legacy TimeTrack',
  };
}

/// One stop visit in a trip's GTFS-Realtime update: the feed's own prediction there.
class FeedStopTime {
  const FeedStopTime({this.time, this.delay});

  /// `departure.time`, else `arrival.time`; null when the feed gave neither.
  final DateTime? time;

  /// The delay of the event [time] came from (so time − delay is that event's timetable time); with no time,
  /// `departure.delay`, else `arrival.delay`. Null when that event has none.
  final Duration? delay;

  /// The predicted time at a visit scheduled at [scheduled]: [time], else [scheduled] + [delay]; null when the
  /// feed gave neither.
  DateTime? predictedFor(DateTime scheduled) => time ?? (delay == null ? null : scheduled.add(delay!));
}

/// Outcome of a live vehicle request.
///
/// A successful request may legitimately contain no vehicles outside service
/// hours. [succeeded] distinguishes that case from an HTTP, network, or payload
/// failure. [source] identifies which backend produced the result.
class TimeTrackFetchResult {
  final List<TimeTrackVehicle> vehicles;
  final String? error;
  final int? statusCode;
  final LiveDataSource? source;

  /// Trip id → stop id → that stop's visits on the trip, in feed order, from the trip-updates feed. Only
  /// [TimeTrackApi.fetchLiveVehiclesResult] fills it; empty otherwise, or when trip updates failed.
  final Map<String, Map<String, List<FeedStopTime>>> stopTimes;

  const TimeTrackFetchResult._({
    required this.vehicles,
    this.error,
    this.statusCode,
    this.source,
    this.stopTimes = const {},
  });

  const TimeTrackFetchResult.success(
    List<TimeTrackVehicle> vehicles, {
    required LiveDataSource source,
    Map<String, Map<String, List<FeedStopTime>>> stopTimes = const {},
  }) : this._(vehicles: vehicles, source: source, stopTimes: stopTimes);

  const TimeTrackFetchResult.failure({required String error, int? statusCode})
    : this._(vehicles: const [], error: error, statusCode: statusCode);

  bool get succeeded => error == null;
}

/// Metrobus live-data client.
///
/// Metrobus now publishes standard GTFS-Realtime Vehicle Positions and Trip
/// Updates. Those feeds are preferred because they give explicit physical
/// vehicle and trip identifiers. The JSON endpoint backing Metrobus Mobile's
/// fleet view is the first fallback, followed by the older TimeTrack JSON API.
class TimeTrackApi {
  static const _vehiclePositionsUrl =
      'https://www.mbusapi.ca/gtfsrt/vehiclepositions';
  static const _tripUpdatesUrl = 'https://www.mbusapi.ca/gtfsrt/tripupdates';
  static const _fleetRouteStatusUrl =
      'https://www.metrobusmobile.com/fleetview.asp?type=routestatus';
  static const _legacyUrl = 'https://www.metrobus.co.ca/api/timetrack/json/';

  final http.Client _client;

  TimeTrackApi({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch all current vehicle positions.
  ///
  /// Returns an empty list on error. Call [fetchVehiclesResult] when the
  /// failure state matters.
  Future<List<TimeTrackVehicle>> fetchVehicles() async {
    return (await fetchVehiclesResult()).vehicles;
  }

  /// Fetch current positions with an ordered backend fallback chain.
  Future<TimeTrackFetchResult> fetchVehiclesResult() async {
    final realtimeResult = await _fetchGtfsRealtime();
    if (realtimeResult != null) return realtimeResult;

    final fleetResult = await _fetchFleetView();
    if (fleetResult != null) return fleetResult;

    return _fetchLegacyTimeTrack();
  }

  /// Fetch current positions from the two GTFS-Realtime feeds only (Vehicle Positions and Trip Updates).
  ///
  /// The lean check for the arrival-alert watcher, which needs a vehicle's trip, timestamp and schedule
  /// difference, and each trip's per-stop times ([TimeTrackFetchResult.stopTimes], read from the same
  /// trip-updates response): no Fleet View route status, no fallbacks. Positions failing is a failure
  /// result. The vehicles are parsed as [fetchVehiclesResult] parses them, so they carry the same
  /// schedule difference.
  Future<TimeTrackFetchResult> fetchLiveVehiclesResult() async {
    final result = await _fetchGtfsRealtime(includeRouteStatus: false, includeStopTimes: true);
    return result ??
        const TimeTrackFetchResult.failure(error: 'GTFS-Realtime vehicle positions unavailable');
  }

  Future<TimeTrackFetchResult?> _fetchGtfsRealtime({
    bool includeRouteStatus = true,
    bool includeStopTimes = false,
  }) async {
    // Start all requests together. Vehicle Positions is required; Trip Updates
    // and Fleet View route metadata are optional enrichments.
    final positionsFuture = _tryGet(_vehiclePositionsUrl);
    final updatesFuture = _tryGet(_tripUpdatesUrl);
    final routeStatusFuture = includeRouteStatus
        ? _tryGet(_fleetRouteStatusUrl)
        : Future<http.Response?>.value(null);
    final responses = await Future.wait([
      positionsFuture,
      updatesFuture,
      routeStatusFuture,
    ]);

    final positionsResponse = responses[0];
    if (positionsResponse == null || positionsResponse.statusCode != 200) {
      return null;
    }

    try {
      final positionsFeed = FeedMessage.fromBuffer(positionsResponse.bodyBytes);
      if (!positionsFeed.hasHeader() ||
          positionsFeed.header.gtfsRealtimeVersion.isEmpty) {
        return null;
      }
      final tripUpdates = _parseTripUpdates(responses[1]);
      final routeStatuses = _parseFleetRouteStatuses(responses[2]);
      final vehicles = <TimeTrackVehicle>[];

      for (final entity in positionsFeed.entity) {
        if (!entity.hasVehicle()) continue;
        final vehiclePosition = entity.vehicle;
        if (!vehiclePosition.hasPosition() || !vehiclePosition.hasTrip()) {
          continue;
        }

        final tripId = vehiclePosition.trip.tripId.trim();
        final routeId = vehiclePosition.trip.routeId.trim();
        final routeNumber = int.tryParse(routeId) ?? 0;
        final vehicleId = _normalizeVehicleId(
          vehiclePosition.hasVehicle() ? vehiclePosition.vehicle.id : entity.id,
        );
        if (vehicleId.isEmpty) continue;

        final routeStatus =
            routeStatuses['$vehicleId|$routeNumber'] ??
            routeStatuses['$vehicleId|'];
        final timing = _tripTiming(
          tripUpdates[tripId],
          currentStopSequence: vehiclePosition.hasCurrentStopSequence()
              ? vehiclePosition.currentStopSequence
              : null,
        );
        final delaySeconds = timing.delaySeconds;
        final delayMins = delaySeconds == null
            ? null
            : (delaySeconds / 60).round();
        // Legacy consumers expect positive = ahead, negative = behind.
        final scheduleDifferenceMins = delayMins == null ? 0 : -delayMins;
        final routeStatusText = _readString(
          routeStatus,
          'opStatus',
        ).toUpperCase();
        final status = routeStatusText == 'NO DATA'
            ? routeStatusText
            : delayMins == null
            ? routeStatusText
            : _delayStatus(delayMins);

        final measuredAt = vehiclePosition.hasTimestamp()
            ? DateTime.fromMillisecondsSinceEpoch(
                vehiclePosition.timestamp.toInt() * 1000,
                isUtc: true,
              ).toLocal()
            : DateTime.now();
        final block = _readString(routeStatus, 'block');
        final currentRoute = block.isNotEmpty ? block : routeId.padLeft(2, '0');
        final routeRun = currentRoute.isNotEmpty
            ? 'Rt $currentRoute'
            : 'trip:$tripId';
        final position = vehiclePosition.position;
        final currentLocation = _readString(routeStatus, 'stopName').isNotEmpty
            ? _readString(routeStatus, 'stopName')
            : _readString(routeStatus, 'nearestStopName');

        vehicles.add(
          TimeTrackVehicle(
            routeRun: routeRun,
            currentRoute: currentRoute,
            routeNumber: routeNumber,
            vehicle: vehicleId,
            timeStamp: measuredAt.toIso8601String(),
            deviation: _delayDescription(delayMins),
            currentLocation: currentLocation,
            busLat: position.latitude,
            busLon: position.longitude,
            heading: position.hasBearing() ? position.bearing.toString() : '',
            // Metrobus currently publishes the same numeric km/h value in
            // both this field and its Fleet View JSON, despite GTFS-Realtime
            // specifying m/s. Keep the agency value in the km/h unit expected
            // by the map's motion pipeline instead of multiplying it by 3.6.
            speed: position.hasSpeed() ? position.speed : 0.0,
            positionTime: measuredAt.toIso8601String(),
            positionTimeSeconds: _secondsSinceMidnight(measuredAt),
            gtfsTripHeadsign: _readString(routeStatus, 'headsign'),
            gtfsServiceId: '',
            gtfsStopSequenceStatus: status,
            // GTFS-Realtime has no "minutes to the closest stop"; the delay
            // is reported separately (gtfsStopSequenceSchedDifferenceMins).
            gtfsStopSequenceMinsFromStop: 0,
            gtfsStopSequenceDeviation: _delayDescription(delayMins),
            gtfsStopSequenceClosestStop: vehiclePosition.stopId.isNotEmpty
                ? vehiclePosition.stopId
                : _readString(routeStatus, 'nearestStopName'),
            gtfsStopSequenceSchedDifferenceMins: scheduleDifferenceMins,
            gtfsTripId: tripId,
            shortStatus: _shortStatus(delayMins),
            departureTimeAtClosestStop: timing.scheduledDepartureSeconds ?? 0,
          ),
        );
      }

      return TimeTrackFetchResult.success(
        vehicles,
        source: LiveDataSource.gtfsRealtime,
        stopTimes: includeStopTimes ? _stopTimesOf(tripUpdates) : const {},
      );
    } catch (error) {
      _debugLog('Could not parse GTFS-Realtime: $error');
      return null;
    }
  }

  /// Fetch the JSON route-status data backing Metrobus Mobile's fleet view.
  Future<TimeTrackFetchResult?> _fetchFleetView() async {
    final response = await _tryGet(_fleetRouteStatusUrl);
    if (response == null || response.statusCode != 200) return null;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return null;
      final vehicles = decoded
          .whereType<Map>()
          .map((row) => _fleetRowToVehicle(Map<String, dynamic>.from(row)))
          .whereType<TimeTrackVehicle>()
          .toList();
      return TimeTrackFetchResult.success(
        vehicles,
        source: LiveDataSource.fleetView,
      );
    } catch (error) {
      _debugLog('Could not parse Fleet View: $error');
      return null;
    }
  }

  Future<TimeTrackFetchResult> _fetchLegacyTimeTrack() async {
    try {
      final response = await _client
          .get(Uri.parse(_legacyUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return _failure(
          'All live feeds failed; legacy TimeTrack returned '
          'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final list = _decodeVehicleList(response.body);
      if (list == null) {
        return _failure('All Metrobus live feeds returned invalid payloads');
      }

      final vehicles = list
          .whereType<Map>()
          .map(
            (json) =>
                TimeTrackVehicle.fromJson(Map<String, dynamic>.from(json)),
          )
          .map(_normalizeLegacyVehicle)
          .toList();
      return TimeTrackFetchResult.success(
        vehicles,
        source: LiveDataSource.legacyTimeTrack,
      );
    } catch (error) {
      return _failure('All Metrobus live feeds failed: $error');
    }
  }

  Future<http.Response?> _tryGet(String url) async {
    try {
      return await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  Map<String, TripUpdate> _parseTripUpdates(http.Response? response) {
    if (response == null || response.statusCode != 200) return const {};
    try {
      final feed = FeedMessage.fromBuffer(response.bodyBytes);
      return {
        for (final entity in feed.entity)
          if (entity.hasTripUpdate() &&
              entity.tripUpdate.hasTrip() &&
              entity.tripUpdate.trip.tripId.isNotEmpty)
            entity.tripUpdate.trip.tripId: entity.tripUpdate,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Each trip's stop visits, keyed by stop id: the feed's departure time, else its arrival time, and the delay.
  static Map<String, Map<String, List<FeedStopTime>>> _stopTimesOf(Map<String, TripUpdate> updates) {
    final result = <String, Map<String, List<FeedStopTime>>>{};
    updates.forEach((tripId, update) {
      final stops = <String, List<FeedStopTime>>{};
      for (final s in update.stopTimeUpdate) {
        if (s.stopId.isEmpty) continue;
        final timed = s.hasDeparture() && s.departure.hasTime()
            ? s.departure
            : s.hasArrival() && s.arrival.hasTime()
            ? s.arrival
            : null;
        // The delay comes from the same event as the time, so time − delay is that event's timetable time.
        final delayed = timed != null
            ? (timed.hasDelay() ? timed : null)
            : s.hasDeparture() && s.departure.hasDelay()
            ? s.departure
            : s.hasArrival() && s.arrival.hasDelay()
            ? s.arrival
            : null;
        (stops[s.stopId] ??= []).add(
          FeedStopTime(
            time: timed == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(timed.time.toInt() * 1000),
            delay: delayed == null ? null : Duration(seconds: delayed.delay),
          ),
        );
      }
      if (stops.isNotEmpty) result[tripId] = stops;
    });
    return result;
  }

  Map<String, Map<String, dynamic>> _parseFleetRouteStatuses(
    http.Response? response,
  ) {
    if (response == null || response.statusCode != 200) return const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const {};
      final result = <String, Map<String, dynamic>>{};
      for (final raw in decoded.whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final vehicle = _normalizeVehicleId(_readString(row, 'vehicle'));
        if (vehicle.isEmpty) continue;
        final route = _readInt(row, 'routeId');
        result['$vehicle|$route'] = row;
        result.putIfAbsent('$vehicle|', () => row);
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  ({int? delaySeconds, int? scheduledDepartureSeconds}) _tripTiming(
    TripUpdate? update, {
    required int? currentStopSequence,
  }) {
    if (update == null) {
      return (delaySeconds: null, scheduledDepartureSeconds: null);
    }

    TripUpdate_StopTimeUpdate? selected;
    if (currentStopSequence != null) {
      for (final stop in update.stopTimeUpdate) {
        if (stop.hasStopSequence() &&
            stop.stopSequence >= currentStopSequence) {
          selected = stop;
          break;
        }
      }
    }
    if (selected == null && update.stopTimeUpdate.isNotEmpty) {
      selected = update.stopTimeUpdate.first;
    }

    final event = selected == null
        ? null
        : selected.hasDeparture()
        ? selected.departure
        : selected.hasArrival()
        ? selected.arrival
        : null;
    final delaySeconds = event != null && event.hasDelay()
        ? event.delay
        : update.hasDelay()
        ? update.delay
        : null;

    int? scheduledDepartureSeconds;
    if (event != null && event.hasTime() && delaySeconds != null) {
      final scheduledAt = DateTime.fromMillisecondsSinceEpoch(
        (event.time.toInt() - delaySeconds) * 1000,
        isUtc: true,
      ).toLocal();
      scheduledDepartureSeconds = _secondsSinceMidnight(scheduledAt);
    }

    return (
      delaySeconds: delaySeconds,
      scheduledDepartureSeconds: scheduledDepartureSeconds,
    );
  }

  TimeTrackVehicle? _fleetRowToVehicle(Map<String, dynamic> row) {
    final routeNumber = _readInt(row, 'routeId');
    final vehicle = _normalizeVehicleId(_readString(row, 'vehicle'));
    final lat = _readDouble(row, 'latitude');
    final lon = _readDouble(row, 'longitude');
    if (vehicle.isEmpty || lat == 0.0 || lon == 0.0) return null;

    final block = _readString(row, 'block');
    final opStatus = _readString(row, 'opStatus').toUpperCase();
    final rawMins = _readInt(row, 'minsOffSchedule');
    final scheduleDifferenceMins = switch (opStatus) {
      'BEHIND' || 'LATE' => -rawMins.abs(),
      'EARLY' || 'AHEAD' => rawMins.abs(),
      _ => 0,
    };
    // 'NO DATA', empty or unrecognised statuses carry no delay; reporting 0
    // would read as "on time". Same as the GTFS-Realtime path with no delay.
    final delayKnown = switch (opStatus) {
      'BEHIND' || 'LATE' || 'EARLY' || 'AHEAD' || 'ON TIME' => true,
      _ => false,
    };
    final int? delayMins = delayKnown ? -scheduleDifferenceMins : null;
    final positionTime = _readString(row, 'positionTime');

    return TimeTrackVehicle(
      routeRun: block.isNotEmpty ? 'Rt $block' : 'route:$routeNumber',
      currentRoute: block,
      routeNumber: routeNumber,
      vehicle: vehicle,
      timeStamp: positionTime,
      deviation: _delayDescription(delayMins),
      currentLocation: _readString(row, 'stopName'),
      busLat: lat,
      busLon: lon,
      heading: _readString(row, 'heading'),
      speed: _readDouble(row, 'speed'),
      positionTime: positionTime,
      positionTimeSeconds: _parseClockSeconds(positionTime),
      gtfsTripHeadsign: _readString(row, 'headsign'),
      gtfsServiceId: '',
      gtfsStopSequenceStatus: opStatus,
      // Fleet View has no "minutes to the closest stop" either; the delay is
      // reported separately (gtfsStopSequenceSchedDifferenceMins).
      gtfsStopSequenceMinsFromStop: 0,
      gtfsStopSequenceDeviation: _delayDescription(delayMins),
      gtfsStopSequenceClosestStop: _readString(row, 'nearestStopName'),
      gtfsStopSequenceSchedDifferenceMins: scheduleDifferenceMins,
      gtfsTripId: '',
      shortStatus: _shortStatus(delayMins),
      departureTimeAtClosestStop: 0,
    );
  }

  TimeTrackVehicle _normalizeLegacyVehicle(TimeTrackVehicle vehicle) {
    final normalized = _normalizeVehicleId(vehicle.vehicle);
    if (normalized == vehicle.vehicle) return vehicle;
    return TimeTrackVehicle(
      routeRun: vehicle.routeRun,
      currentRoute: vehicle.currentRoute,
      routeNumber: vehicle.routeNumber,
      vehicle: normalized,
      timeStamp: vehicle.timeStamp,
      deviation: vehicle.deviation,
      currentLocation: vehicle.currentLocation,
      busLat: vehicle.busLat,
      busLon: vehicle.busLon,
      heading: vehicle.heading,
      speed: vehicle.speed,
      positionTime: vehicle.positionTime,
      positionTimeSeconds: vehicle.positionTimeSeconds,
      gtfsTripHeadsign: vehicle.gtfsTripHeadsign,
      gtfsServiceId: vehicle.gtfsServiceId,
      gtfsStopSequenceStatus: vehicle.gtfsStopSequenceStatus,
      gtfsStopSequenceMinsFromStop: vehicle.gtfsStopSequenceMinsFromStop,
      gtfsStopSequenceDeviation: vehicle.gtfsStopSequenceDeviation,
      gtfsStopSequenceClosestStop: vehicle.gtfsStopSequenceClosestStop,
      gtfsStopSequenceSchedDifferenceMins:
          vehicle.gtfsStopSequenceSchedDifferenceMins,
      gtfsTripId: vehicle.gtfsTripId,
      shortStatus: vehicle.shortStatus,
      departureTimeAtClosestStop: vehicle.departureTimeAtClosestStop,
    );
  }

  String _normalizeVehicleId(String value) {
    return value.trim().replaceFirst(RegExp(r'^0+(?=\d)'), '');
  }

  int _secondsSinceMidnight(DateTime value) =>
      value.hour * 3600 + value.minute * 60 + value.second;

  int _parseClockSeconds(String value) {
    final match = RegExp(
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AP]M)?',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return 0;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final second = int.tryParse(match.group(3) ?? '') ?? 0;
    final marker = match.group(4)?.toUpperCase();
    if (marker == 'PM' && hour != 12) hour += 12;
    if (marker == 'AM' && hour == 12) hour = 0;
    return hour * 3600 + minute * 60 + second;
  }

  String _delayStatus(int delayMins) {
    if (delayMins > 1) return 'BEHIND';
    if (delayMins < -1) return 'AHEAD';
    return 'ON TIME';
  }

  String _delayDescription(int? delayMins) {
    if (delayMins == null) return '';
    if (delayMins > 1) return '$delayMins MINS BEHIND';
    if (delayMins < -1) return '${delayMins.abs()} MINS AHEAD';
    return 'ON TIME';
  }

  String _shortStatus(int? delayMins) {
    if (delayMins == null) return '';
    if (delayMins > 1) return 'B$delayMins';
    if (delayMins < -1) return 'A${delayMins.abs()}';
    return 'OT';
  }

  String _readString(Map<String, dynamic>? row, String key) =>
      row?[key]?.toString().trim() ?? '';

  int _readInt(Map<String, dynamic>? row, String key) {
    final value = row?[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _readDouble(Map<String, dynamic>? row, String key) {
    final value = row?[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  TimeTrackFetchResult _failure(String message, {int? statusCode}) {
    _debugLog(message);
    return TimeTrackFetchResult.failure(error: message, statusCode: statusCode);
  }

  List<dynamic>? _decodeVehicleList(String body) {
    for (final candidate in _decodeCandidates(body)) {
      final decoded = _tryDecode(candidate);
      final extracted = _extractVehicleList(decoded);
      if (extracted != null) return extracted;

      // The older endpoint sometimes included text around the JSON array.
      final firstArray = candidate.indexOf('[');
      final lastArray = candidate.lastIndexOf(']');
      if (firstArray == -1 || lastArray == -1 || lastArray <= firstArray) {
        continue;
      }

      final sliced = candidate.substring(firstArray, lastArray + 1);
      final slicedExtracted = _extractVehicleList(_tryDecode(sliced));
      if (slicedExtracted != null) return slicedExtracted;
    }
    return null;
  }

  Iterable<String> _decodeCandidates(String body) sync* {
    yield body;
    final sanitized = _sanitizeJsonText(body);
    if (sanitized != body) yield sanitized;
  }

  dynamic _tryDecode(String input) {
    try {
      return jsonDecode(input);
    } catch (_) {
      return null;
    }
  }

  List<dynamic>? _extractVehicleList(dynamic decoded) {
    if (decoded is List<dynamic>) return decoded;
    if (decoded is Map<String, dynamic>) {
      for (final key in const ['vehicles', 'data', 'results', 'items']) {
        final value = decoded[key];
        if (value is List<dynamic>) return value;
      }
    }
    return null;
  }

  String _sanitizeJsonText(String input) {
    return input.replaceAll(RegExp(r'[\u0000-\u001F]'), ' ');
  }

  /// Build a lookup map of trip_id → vehicle for arrival matching.
  ///
  /// The feed can report one trip on two vehicles: a ghost frozen at an old
  /// position next to the bus really running it. The one whose position is
  /// newest at [now] wins, so a fix over 5 minutes old never beats a fresher
  /// one. A vehicle with no usable position time ranks as exactly 5 minutes
  /// old; among equals the later one wins.
  static Map<String, TimeTrackVehicle> buildTripIndex(
    List<TimeTrackVehicle> vehicles, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final map = <String, TimeTrackVehicle>{};
    final ages = <String, Duration>{};
    for (final vehicle in vehicles) {
      final trip = vehicle.gtfsTripId;
      if (trip.isEmpty) continue;
      final age = _positionAge(vehicle, at) ?? _unknownPositionAge;
      final best = ages[trip];
      if (best == null || age <= best) {
        map[trip] = vehicle;
        ages[trip] = age;
      }
    }
    return map;
  }

  static const Duration _unknownPositionAge = Duration(minutes: 5);

  /// How old [v]'s position is at [now]: from its full timestamp when it has
  /// one, else from its seconds of the day, read as the most recent such
  /// time (so 00:00:30 is newer than 23:40 just after midnight).
  static Duration? _positionAge(TimeTrackVehicle v, DateTime now) {
    final stamp = DateTime.tryParse(v.positionTime);
    if (stamp != null) return now.difference(stamp);
    final seconds = v.positionTimeSeconds;
    if (seconds <= 0 || seconds >= Duration.secondsPerDay) return null;
    final nowSeconds = now.hour * 3600 + now.minute * 60 + now.second;
    var age = (nowSeconds - seconds) % Duration.secondsPerDay;
    if (age > Duration.secondsPerDay ~/ 2) age -= Duration.secondsPerDay; // slightly ahead of us
    return Duration(seconds: age);
  }

  void dispose() {
    _client.close();
  }
}

void _debugLog(String message) {
  assert(() {
    developer.log(message, name: 'BusBoard.LiveData');
    return true;
  }());
}

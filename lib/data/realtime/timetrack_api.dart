import 'dart:convert';
import 'package:http/http.dart' as http;
import 'timetrack_models.dart';

/// Client for the Metrobus TimeTrack JSON API.
///
/// Fetches live vehicle positions and schedule adherence data.
/// Returns empty list on any error (graceful degradation).
class TimeTrackApi {
  static const _url = 'https://www.metrobus.co.ca/api/timetrack/json/';

  final http.Client _client;

  TimeTrackApi({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch all current vehicle positions from TimeTrack.
  ///
  /// Returns empty list on error.
  Future<List<TimeTrackVehicle>> fetchVehicles() async {
    try {
      final response = await _client
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return [];
      }

      final list = _decodeVehicleList(response.body);
      return list
          .whereType<Map>()
          .map(
            (json) =>
                TimeTrackVehicle.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<dynamic> _decodeVehicleList(String body) {
    for (final candidate in _decodeCandidates(body)) {
      final decoded = _tryDecode(candidate);
      final extracted = _extractVehicleList(decoded);
      if (extracted != null) return extracted;

      // Some endpoint responses include extra text around a JSON array.
      final firstArray = candidate.indexOf('[');
      final lastArray = candidate.lastIndexOf(']');
      if (firstArray == -1 || lastArray == -1 || lastArray <= firstArray) {
        continue;
      }

      final sliced = candidate.substring(firstArray, lastArray + 1);
      final slicedDecoded = _tryDecode(sliced);
      final slicedExtracted = _extractVehicleList(slicedDecoded);
      if (slicedExtracted != null) return slicedExtracted;
    }
    return const [];
  }

  Iterable<String> _decodeCandidates(String body) sync* {
    yield body;
    final sanitized = _sanitizeJsonText(body);
    if (sanitized != body) {
      yield sanitized;
    }
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
    // TimeTrack occasionally includes raw control characters in strings
    // (for example, newline characters inside bulletin fields), which makes
    // otherwise JSON-like payloads fail strict decoding.
    return input.replaceAll(RegExp(r'[\u0000-\u001F]'), ' ');
  }

  /// Build a lookup map of trip_id → TimeTrackVehicle for fast matching.
  static Map<String, TimeTrackVehicle> buildTripIndex(
    List<TimeTrackVehicle> vehicles,
  ) {
    final map = <String, TimeTrackVehicle>{};
    for (final v in vehicles) {
      if (v.gtfsTripId.isNotEmpty) {
        map[v.gtfsTripId] = v;
      }
    }
    return map;
  }

  void dispose() {
    _client.close();
  }
}

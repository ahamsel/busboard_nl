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

      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList
          .map(
            (json) => TimeTrackVehicle.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return [];
    }
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

/// TimeTrack live vehicle data model.
///
/// Based on the JSON response from:
/// https://www.metrobus.co.ca/api/timetrack/json/
class TimeTrackVehicle {
  final String routeRun;
  final String currentRoute;
  final int routeNumber;
  final String vehicle;
  final String timeStamp;
  final String deviation;
  final String currentLocation;
  final double busLat;
  final double busLon;
  final String heading;
  final double speed;
  final String positionTime;
  final int positionTimeSeconds;
  final String gtfsTripHeadsign;
  final String gtfsServiceId;
  final String gtfsStopSequenceStatus;
  final int gtfsStopSequenceMinsFromStop;
  final String gtfsStopSequenceDeviation;
  final String gtfsStopSequenceClosestStop;
  final int gtfsStopSequenceSchedDifferenceMins;
  final String gtfsTripId;
  final String shortStatus;
  final int departureTimeAtClosestStop;

  const TimeTrackVehicle({
    required this.routeRun,
    required this.currentRoute,
    required this.routeNumber,
    required this.vehicle,
    required this.timeStamp,
    required this.deviation,
    required this.currentLocation,
    required this.busLat,
    required this.busLon,
    required this.heading,
    required this.speed,
    required this.positionTime,
    required this.positionTimeSeconds,
    required this.gtfsTripHeadsign,
    required this.gtfsServiceId,
    required this.gtfsStopSequenceStatus,
    required this.gtfsStopSequenceMinsFromStop,
    required this.gtfsStopSequenceDeviation,
    required this.gtfsStopSequenceClosestStop,
    required this.gtfsStopSequenceSchedDifferenceMins,
    required this.gtfsTripId,
    required this.shortStatus,
    required this.departureTimeAtClosestStop,
  });

  factory TimeTrackVehicle.fromJson(Map<String, dynamic> json) {
    String readString(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null) return value.toString().trim();
      }
      return '';
    }

    int readInt(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      return 0;
    }

    double readDouble(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is double) return value;
        if (value is num) return value.toDouble();
        final parsed = double.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      return 0.0;
    }

    return TimeTrackVehicle(
      routeRun: readString(['routerun', 'route_run', 'routeRun']),
      currentRoute: readString(['current_route', 'currentRoute', 'route']),
      routeNumber: readInt(['routenumber', 'route_number', 'routeNumber']),
      vehicle: readString(['vehicle', 'bus', 'vehicle_id', 'vehicleId']),
      timeStamp: readString(['time_stamp', 'timeStamp']),
      deviation: readString(['deviation']),
      currentLocation: readString(['current_location', 'currentLocation']),
      busLat: readDouble(['bus_lat', 'busLat', 'lat', 'latitude']),
      busLon: readDouble(['bus_lon', 'busLon', 'lon', 'lng', 'longitude']),
      heading: readString(['heading', 'bearing']),
      speed: readDouble(['speed']),
      positionTime: readString(['position_time', 'positionTime']),
      positionTimeSeconds: readInt([
        'position_time_seconds',
        'positionTimeSeconds',
      ]),
      gtfsTripHeadsign: readString([
        'gtfs_trip_headsign',
        'gtfsTripHeadsign',
        'headsign',
      ]),
      gtfsServiceId: readString(['gtfs_service_id', 'gtfsServiceId']),
      gtfsStopSequenceStatus: readString([
        'gtfs_stop_sequence_status',
        'gtfsStopSequenceStatus',
      ]),
      gtfsStopSequenceMinsFromStop: readInt([
        'gtfs_stop_sequence_mins_from_stop',
        'gtfsStopSequenceMinsFromStop',
      ]),
      gtfsStopSequenceDeviation: readString([
        'gtfs_stop_sequence_deviation',
        'gtfsStopSequenceDeviation',
      ]),
      gtfsStopSequenceClosestStop: readString([
        'gtfs_stop_sequence_closest_stop',
        'gtfsStopSequenceClosestStop',
      ]),
      gtfsStopSequenceSchedDifferenceMins: readInt([
        'gtfs_stop_sequence_sched_difference_mins',
        'gtfsStopSequenceSchedDifferenceMins',
      ]),
      gtfsTripId: readString([
        'gtfs_trip_id',
        'gtfs_stop_sequence_trip_id',
        'trip_id',
        'gtfsTripId',
      ]),
      shortStatus: readString(['shortstatus', 'short_status', 'shortStatus']),
      departureTimeAtClosestStop: readInt([
        'departure_time_at_closest_stop',
        'departureTimeAtClosestStop',
      ]),
    );
  }

  /// Human-readable status: AHEAD, BEHIND, ON TIME, or empty.
  String get statusLabel {
    if (shortStatus.startsWith('A')) return 'AHEAD';
    if (shortStatus.startsWith('B')) return 'BEHIND';
    if (shortStatus == 'OT') return 'ON TIME';
    return '';
  }

  @override
  String toString() =>
      'TimeTrackVehicle($routeRun vehicle=$vehicle '
      'trip=$gtfsTripId diff=${gtfsStopSequenceSchedDifferenceMins}min)';
}

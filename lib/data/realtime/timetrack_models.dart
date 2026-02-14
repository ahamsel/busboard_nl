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
    return TimeTrackVehicle(
      routeRun: json['routerun'] as String? ?? '',
      currentRoute: json['current_route'] as String? ?? '',
      routeNumber: (json['routenumber'] as num?)?.toInt() ?? 0,
      vehicle: json['vehicle'] as String? ?? '',
      timeStamp: json['time_stamp'] as String? ?? '',
      deviation: json['deviation'] as String? ?? '',
      currentLocation: json['current_location'] as String? ?? '',
      busLat: double.tryParse(json['bus_lat']?.toString() ?? '') ?? 0.0,
      busLon: double.tryParse(json['bus_lon']?.toString() ?? '') ?? 0.0,
      heading: json['heading'] as String? ?? '',
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      positionTime: json['position_time'] as String? ?? '',
      positionTimeSeconds:
          (json['position_time_seconds'] as num?)?.toInt() ?? 0,
      gtfsTripHeadsign: json['gtfs_trip_headsign'] as String? ?? '',
      gtfsServiceId: json['gtfs_service_id'] as String? ?? '',
      gtfsStopSequenceStatus:
          json['gtfs_stop_sequence_status'] as String? ?? '',
      gtfsStopSequenceMinsFromStop:
          (json['gtfs_stop_sequence_mins_from_stop'] as num?)?.toInt() ?? 0,
      gtfsStopSequenceDeviation:
          json['gtfs_stop_sequence_deviation'] as String? ?? '',
      gtfsStopSequenceClosestStop:
          json['gtfs_stop_sequence_closest_stop'] as String? ?? '',
      gtfsStopSequenceSchedDifferenceMins:
          (json['gtfs_stop_sequence_sched_difference_mins'] as num?)?.toInt() ??
          0,
      gtfsTripId: json['gtfs_trip_id'] as String? ?? '',
      shortStatus: json['shortstatus'] as String? ?? '',
      departureTimeAtClosestStop:
          int.tryParse(
            json['departure_time_at_closest_stop']?.toString() ?? '',
          ) ??
          0,
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

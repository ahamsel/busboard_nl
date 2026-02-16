/// A single raw GPS observation from a bus.
class BusObservation {
  final DateTime timestamp;
  final DateTime measurementTime;
  final double lat;
  final double lon;
  final double heading;
  final double speed;
  final String? gtfsTripId;
  final double? progressAlongRoute;
  final bool rejected;

  /// Shape progress (meters) of the stop the bus is approaching,
  /// resolved from the API's departureTimeAtClosestStop + trip ID.
  final double? closestStopProgressM;

  /// Minutes until the bus reaches the closest stop (from API).
  final int? minsFromClosestStop;

  const BusObservation({
    required this.timestamp,
    required this.measurementTime,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.speed,
    this.gtfsTripId,
    this.progressAlongRoute,
    this.rejected = false,
    this.closestStopProgressM,
    this.minsFromClosestStop,
  });

  BusObservation copyWith({
    bool? rejected,
    double? progressAlongRoute,
    double? closestStopProgressM,
    int? minsFromClosestStop,
  }) {
    return BusObservation(
      timestamp: timestamp,
      measurementTime: measurementTime,
      lat: lat,
      lon: lon,
      heading: heading,
      speed: speed,
      gtfsTripId: gtfsTripId,
      progressAlongRoute: progressAlongRoute ?? this.progressAlongRoute,
      rejected: rejected ?? this.rejected,
      closestStopProgressM:
          closestStopProgressM ?? this.closestStopProgressM,
      minsFromClosestStop:
          minsFromClosestStop ?? this.minsFromClosestStop,
    );
  }
}

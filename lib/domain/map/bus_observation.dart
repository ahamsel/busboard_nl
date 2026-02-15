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
  });

  BusObservation copyWith({bool? rejected, double? progressAlongRoute}) {
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
    );
  }
}

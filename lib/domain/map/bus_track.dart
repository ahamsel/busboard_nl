/// One GPS fix of a tracked bus, with its place on the trip's shape.
class TrackFix {
  const TrackFix({
    required this.gpsTime,
    required this.fetchTime,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.speedKmh,
    this.tripId,
    this.shapeId,
    this.progress,
    this.snappedLat,
    this.snappedLon,
    this.offRoute = false,
    this.schedDiffMins,
  });

  /// When the bus measured this position (from the feed's position time).
  final DateTime gpsTime;

  /// When we received it.
  final DateTime fetchTime;
  final double lat;
  final double lon;
  final double heading;
  final double speedKmh;
  final String? tripId;
  final String? shapeId;

  /// Metres along [shapeId]; null when off route or without a shape.
  final double? progress;
  final double? snappedLat;
  final double? snappedLon;

  /// More than RouteGeometry.offRouteMeters from the shape.
  final bool offRoute;

  /// Schedule difference reported with this fix, in minutes: positive = ahead
  /// (early), negative = behind (late), null = the feed reported no delay.
  final int? schedDiffMins;
}

/// The recent fixes of one physical bus (keyed by vehicle ID).
class BusTrack {
  BusTrack({
    required this.vehicleId,
    required this.routeNumber,
    required this.routeRun,
    required this.headsign,
    required this.fixes,
    required this.lastFixAt,
  });

  final String vehicleId;
  int routeNumber;
  String routeRun;
  String headsign;

  /// Oldest first; never empty.
  final List<TrackFix> fixes;

  /// Fetch time of the newest fix with a new GPS time.
  DateTime lastFixAt;

  TrackFix get latest => fixes.last;
}

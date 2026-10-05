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
    this.snapProgress,
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

  /// Metres along [shapeId]; null when off route, without a shape, or while
  /// the bus runs the shape backward (see [snapProgress]).
  final double? progress;

  /// Where the fix snapped along [shapeId], kept even when [progress] is
  /// withheld because the bus is running the shape backward (BusTrackStore's
  /// reverse rule): the next fix's snap window still follows the bus.
  /// Null when off route or without a shape.
  final double? snapProgress;
  final double? snappedLat;
  final double? snappedLon;

  /// More than RouteGeometry.offRouteMeters from the shape.
  final bool offRoute;

  /// Schedule difference reported with this fix, in minutes: positive = ahead
  /// (early), negative = behind (late), null = the feed reported no delay.
  final int? schedDiffMins;

  /// Whether BusTrackStore's reverse rule withheld [progress] (the snap is
  /// kept in [snapProgress]).
  bool get progressWithheld => progress == null && snapProgress != null;

  /// This fix with [progress] and the snapped place withheld.
  TrackFix withheld() => TrackFix(
        gpsTime: gpsTime,
        fetchTime: fetchTime,
        lat: lat,
        lon: lon,
        heading: heading,
        speedKmh: speedKmh,
        tripId: tripId,
        shapeId: shapeId,
        snapProgress: snapProgress,
        offRoute: offRoute,
        schedDiffMins: schedDiffMins,
      );
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

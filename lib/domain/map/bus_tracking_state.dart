import 'bus_track.dart';

enum BusStatus { active, offRoute, stale }

/// What the map and bus sheet know about one physical bus right now: its
/// identity, its latest fix and whether it is still reporting. Where to draw
/// it this frame comes from DelayedTrackRenderer.
class BusTrackingState {
  final String routeRun;
  final String vehicleId;
  final int routeNumber;
  final String headsign;
  final String? currentTripId;
  final String? shapeId;
  final double smoothedLat;
  final double smoothedLon;
  final double smoothedHeading;
  final double? progress;
  final double speedKmh;
  final DateTime lastGpsTime;
  final BusStatus status;
  final DateTime lastUpdateTime;

  const BusTrackingState({
    required this.routeRun,
    required this.vehicleId,
    required this.routeNumber,
    required this.headsign,
    this.currentTripId,
    this.shapeId,
    required this.smoothedLat,
    required this.smoothedLon,
    required this.smoothedHeading,
    this.progress,
    required this.speedKmh,
    required this.lastGpsTime,
    required this.status,
    required this.lastUpdateTime,
  });

  factory BusTrackingState.fromTrack(BusTrack track, {required bool stale}) {
    final f = track.latest;
    return BusTrackingState(
      routeRun: track.routeRun,
      vehicleId: track.vehicleId,
      routeNumber: track.routeNumber,
      headsign: track.headsign,
      currentTripId: f.tripId,
      shapeId: f.shapeId,
      smoothedLat: f.snappedLat ?? f.lat,
      smoothedLon: f.snappedLon ?? f.lon,
      smoothedHeading: f.heading,
      progress: f.progress,
      speedKmh: f.speedKmh,
      lastGpsTime: f.gpsTime,
      status: stale ? BusStatus.stale : (f.offRoute ? BusStatus.offRoute : BusStatus.active),
      lastUpdateTime: track.lastFixAt,
    );
  }
}

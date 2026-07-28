import 'bus_observation.dart';

enum BusStatus { active, stopped, stale, offRoute, backtracking }

/// Smoothed tracking state for a single physical bus.
///
/// The map engine keys by [vehicleId] when Metrobus supplies it, with
/// route-run and trip identifiers used only as fallbacks.
class BusTrackingState {
  final String routeRun;
  final String vehicleId;
  final int routeNumber;
  final String headsign;
  final String? currentTripId;
  final String? shapeId;
  final List<BusObservation> observations;
  final double smoothedLat;
  final double smoothedLon;
  final double smoothedHeading;
  final double? progressAlongRoute;
  final BusStatus status;
  final DateTime lastUpdateTime;

  const BusTrackingState({
    required this.routeRun,
    required this.vehicleId,
    required this.routeNumber,
    required this.headsign,
    this.currentTripId,
    this.shapeId,
    required this.observations,
    required this.smoothedLat,
    required this.smoothedLon,
    required this.smoothedHeading,
    this.progressAlongRoute,
    required this.status,
    required this.lastUpdateTime,
  });

  BusTrackingState copyWith({
    String? routeRun,
    String? vehicleId,
    int? routeNumber,
    String? headsign,
    String? currentTripId,
    String? shapeId,
    List<BusObservation>? observations,
    double? smoothedLat,
    double? smoothedLon,
    double? smoothedHeading,
    double? progressAlongRoute,
    BusStatus? status,
    DateTime? lastUpdateTime,
  }) {
    return BusTrackingState(
      routeRun: routeRun ?? this.routeRun,
      vehicleId: vehicleId ?? this.vehicleId,
      routeNumber: routeNumber ?? this.routeNumber,
      headsign: headsign ?? this.headsign,
      currentTripId: currentTripId ?? this.currentTripId,
      shapeId: shapeId ?? this.shapeId,
      observations: observations ?? this.observations,
      smoothedLat: smoothedLat ?? this.smoothedLat,
      smoothedLon: smoothedLon ?? this.smoothedLon,
      smoothedHeading: smoothedHeading ?? this.smoothedHeading,
      progressAlongRoute: progressAlongRoute ?? this.progressAlongRoute,
      status: status ?? this.status,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
    );
  }
}

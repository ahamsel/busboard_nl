import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';

// An out-and-back shape: ~1 km east along one curb, then ~1 km back west
// along the other curb 8 m north. Both legs share one road, so a GPS fix on
// the outbound leg can be nearer the return leg (the real failure on Metrobus
// routes 10, 14, 21 and others).
const outAndBackShapeId = 'out-and-back';
const outAndBackTripId = 'trip-out-and-back';
const outboundLat = 47.5600;
const returnLat = 47.56007; // ~8 m north
const _west = -52.7600;
const _east = -52.7465; // ~1 km east at this latitude

/// Between the curbs, 2.0 m from the return leg and 5.8 m from the outbound.
const nearReturnCurb = 47.560052;

/// 1.3 m from the outbound leg.
const nearOutboundCurb = 47.560012;

/// Longitude [meters] east of the shape's west end.
double lonAt(double meters) =>
    _west + meters / (111320 * math.cos(outboundLat * math.pi / 180));

List<ShapePoint> outAndBackPoints() {
  final points = <ShapePoint>[];
  var seq = 1;
  for (var i = 0; i <= 10; i++) {
    points.add(ShapePoint(
      shapeId: outAndBackShapeId,
      lat: outboundLat,
      lon: _west + (_east - _west) * i / 10,
      sequence: seq++,
    ));
  }
  for (var i = 10; i >= 0; i--) {
    points.add(ShapePoint(
      shapeId: outAndBackShapeId,
      lat: returnLat,
      lon: _west + (_east - _west) * i / 10,
      sequence: seq++,
    ));
  }
  return points;
}

List<double> cumulativeFor(List<ShapePoint> points) {
  final result = <double>[0];
  for (var i = 1; i < points.length; i++) {
    result.add(result.last +
        NearestStopService.haversineDistance(
          points[i - 1].lat,
          points[i - 1].lon,
          points[i].lat,
          points[i].lon,
        ));
  }
  return result;
}

/// Route 10 on the out-and-back shape. Stops sit between the curbs, nearer
/// the return leg, so a global snap would put outbound stops on the way back:
/// s1 200 m (12:00), s2 500 m (12:01), s3 800 m (12:02) outbound, s4 300 m
/// from the west end on the return leg (12:05).
GtfsRepository outAndBackRepo() {
  final repo = GtfsRepository();
  repo.routesById['r10'] = const RouteInfo(
    routeId: 'r10',
    routeShortName: '10',
    routeLongName: 'Out and back',
  );
  repo.tripsById[outAndBackTripId] = const TripInfo(
    tripId: outAndBackTripId,
    routeId: 'r10',
    serviceId: 'svc',
    tripHeadsign: 'Loop',
    directionId: 0,
    shapeId: outAndBackShapeId,
  );
  final points = outAndBackPoints();
  repo.shapesById[outAndBackShapeId] = points;
  repo.shapeCumulativeDistances[outAndBackShapeId] = cumulativeFor(points);
  final stops = [
    ('s1', 200.0, '12:00:00'),
    ('s2', 500.0, '12:01:00'),
    ('s3', 800.0, '12:02:00'),
    ('s4', 300.0, '12:05:00'),
  ];
  for (var i = 0; i < stops.length; i++) {
    final (id, meters, time) = stops[i];
    repo.stopsById[id] = StopInfo(stopId: id, stopName: id, stopLat: 47.560045, stopLon: lonAt(meters));
    repo.stopTimesByStopId.putIfAbsent(id, () => []).add(StopTimeRow(
          tripId: outAndBackTripId,
          arrivalTime: time,
          departureTime: time,
          stopId: id,
          stopSequence: i + 1,
        ));
  }
  return repo;
}

TimeTrackVehicle fix({
  required double meters,
  required int seconds,
  double lat = nearReturnCurb,
  String vehicle = '2573',
  int routeNumber = 10,
  String routeRun = 'Rt 10',
  String tripId = outAndBackTripId,
  int departureTimeAtClosestStop = 0,
  int schedDifferenceMins = 0,
  String deviation = '',
  double speed = 29,
}) {
  return TimeTrackVehicle(
    routeRun: routeRun,
    currentRoute: routeRun.replaceFirst('Rt ', ''),
    routeNumber: routeNumber,
    vehicle: vehicle,
    timeStamp: '',
    deviation: '',
    currentLocation: '',
    busLat: lat,
    busLon: lonAt(meters),
    heading: '90',
    speed: speed,
    positionTime: '',
    positionTimeSeconds: seconds,
    gtfsTripHeadsign: '',
    gtfsServiceId: '',
    gtfsStopSequenceStatus: 'ON TIME',
    gtfsStopSequenceMinsFromStop: 0,
    gtfsStopSequenceDeviation: deviation,
    gtfsStopSequenceClosestStop: '',
    gtfsStopSequenceSchedDifferenceMins: schedDifferenceMins,
    gtfsTripId: tripId,
    shortStatus: 'OT',
    departureTimeAtClosestStop: departureTimeAtClosestStop,
  );
}

extension TimeTrackVehicleTestCopy on TimeTrackVehicle {
  TimeTrackVehicle copyForTest({String? status, String? shortStatus, double? lat, double? lon}) => TimeTrackVehicle(
        routeRun: routeRun, currentRoute: currentRoute, routeNumber: routeNumber, vehicle: vehicle,
        timeStamp: timeStamp, deviation: deviation, currentLocation: currentLocation,
        busLat: lat ?? busLat, busLon: lon ?? busLon, heading: heading, speed: speed,
        positionTime: positionTime, positionTimeSeconds: positionTimeSeconds,
        gtfsTripHeadsign: gtfsTripHeadsign, gtfsServiceId: gtfsServiceId,
        gtfsStopSequenceStatus: status ?? gtfsStopSequenceStatus,
        gtfsStopSequenceMinsFromStop: gtfsStopSequenceMinsFromStop,
        gtfsStopSequenceDeviation: gtfsStopSequenceDeviation,
        gtfsStopSequenceClosestStop: gtfsStopSequenceClosestStop,
        gtfsStopSequenceSchedDifferenceMins: gtfsStopSequenceSchedDifferenceMins,
        gtfsTripId: gtfsTripId, shortStatus: shortStatus ?? this.shortStatus,
        departureTimeAtClosestStop: departureTimeAtClosestStop,
      );
}

extension TripInfoTestCopy on TripInfo {
  TripInfo copyForTest({required String tripId}) => TripInfo(
        tripId: tripId, routeId: routeId, serviceId: serviceId, tripHeadsign: tripHeadsign,
        directionId: directionId, shapeId: shapeId);
}

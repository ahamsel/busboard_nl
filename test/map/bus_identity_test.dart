import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_motion_engine.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BusMotionEngine engine;
  late DateTime now;

  setUp(() {
    engine = BusMotionEngine(GtfsRepository());
    now = DateTime(2026, 7, 28, 15, 25);
  });

  test('same route-run with different vehicle IDs remains two buses', () {
    engine.processBatch([
      _vehicle(vehicle: '859', routeRun: 'Rt 20-1', lat: 47.53),
      _vehicle(vehicle: '861', routeRun: 'Rt 20-1', lat: 47.54),
    ], now);

    expect(engine.states.keys, containsAll(['859', '861']));
    expect(engine.states, hasLength(2));
  });

  test('duplicate interlined assignments keep one physical bus', () {
    engine.processBatch([
      _vehicle(
        vehicle: '859',
        routeRun: 'Rt 6-1',
        routeNumber: 6,
        status: 'NO DATA',
        shortStatus: 'A3',
        tripId: 'trip-6',
      ),
      _vehicle(
        vehicle: '859',
        routeRun: 'Rt 20-1',
        routeNumber: 20,
        status: 'ON TIME',
        shortStatus: 'OT',
        tripId: 'trip-20',
      ),
    ], now);

    expect(engine.states, hasLength(1));
    expect(engine.states['859']?.routeRun, 'Rt 20-1');
    expect(engine.states['859']?.routeNumber, 20);
    expect(engine.diagnostics.duplicateVehicleAssignments, 1);
  });

  test('a replacement vehicle never inherits the old bus state', () {
    engine.processBatch([
      _vehicle(vehicle: '859', routeRun: 'Rt 20-1', lat: 47.53),
    ], now);
    engine.processBatch([
      _vehicle(vehicle: '861', routeRun: 'Rt 20-1', lat: 47.56),
    ], now.add(const Duration(seconds: 5)));

    expect(engine.states['859']?.status, BusStatus.stale);
    expect(engine.states['861']?.status, isNot(BusStatus.stale));
    expect(engine.states['861']?.observations, hasLength(1));
  });

  test(
    'same physical bus resets progress when its block turns onto a new trip',
    () {
      final routeRepo = _turnaroundRepo();
      final routeEngine = BusMotionEngine(routeRepo);
      final firstPoll = DateTime(2026, 7, 28, 16, 48, 17);

      routeEngine.processBatch([
        _vehicle(
          vehicle: '2574',
          routeRun: 'Rt 03-2',
          routeNumber: 3,
          lat: 47.61782,
          lon: -52.71560,
          tripId: 'outbound',
          positionTimeSeconds: 60497,
        ),
      ], firstPoll);
      final outboundProgress = routeEngine.states['2574']!.progressAlongRoute!;
      expect(outboundProgress, greaterThan(5000));

      final turnaroundPoll = firstPoll.add(const Duration(seconds: 15));
      routeEngine.processBatch([
        _vehicle(
          vehicle: '2574',
          routeRun: 'Rt 03-2',
          routeNumber: 3,
          lat: 47.61842,
          lon: -52.71690,
          tripId: 'inbound',
          positionTimeSeconds: 60512,
        ),
      ], turnaroundPoll);

      final state = routeEngine.states['2574']!;
      expect(state.currentTripId, 'inbound');
      expect(state.status, BusStatus.active);
      expect(state.observations, hasLength(1));
      expect(state.progressAlongRoute, lessThan(500));

      final rendered = routeEngine.interpolate(
        turnaroundPoll.add(const Duration(milliseconds: 300)),
      )['2574']!;
      final distanceFromTurnaround = NearestStopService.haversineDistance(
        rendered.$1,
        rendered.$2,
        47.61842,
        -52.71690,
      );
      expect(distanceFromTurnaround, lessThan(300));
    },
  );

  test('same-trip GPS corrections never render a physical bus backward', () {
    final routeRepo = _turnaroundRepo();
    final routeEngine = BusMotionEngine(routeRepo);
    final firstPoll = DateTime(2026, 7, 28, 16, 50);

    void feed(int seconds, double lat, double lon) {
      routeEngine.processBatch([
        _vehicle(
          vehicle: '2574',
          routeRun: 'Rt 03-2',
          routeNumber: 3,
          lat: lat,
          lon: lon,
          tripId: 'inbound',
          positionTimeSeconds: 60600 + seconds,
        ),
      ], firstPoll.add(Duration(seconds: seconds)));
    }

    feed(0, 47.61842, -52.71690);
    feed(15, 47.61680, -52.71800);
    final forwardTime = firstPoll.add(const Duration(seconds: 15));
    routeEngine.interpolate(forwardTime);
    final highWater = routeEngine.debugRenderedProgressByKey['2574']!;

    // Three consecutive fixes behind the prediction exercise the engine's
    // confirmed-backtracking branch, which previously allowed a visible snap.
    feed(30, 47.61720, -52.71772);
    feed(45, 47.61760, -52.71745);
    feed(60, 47.61800, -52.71718);

    for (var milliseconds = 0; milliseconds <= 1200; milliseconds += 120) {
      routeEngine.interpolate(
        firstPoll.add(Duration(seconds: 60, milliseconds: milliseconds)),
      );
      expect(
        routeEngine.debugRenderedProgressByKey['2574']!,
        greaterThanOrEqualTo(highWater),
      );
    }
  });
}

TimeTrackVehicle _vehicle({
  required String vehicle,
  required String routeRun,
  int routeNumber = 20,
  double lat = 47.53,
  double lon = -52.75,
  String status = 'ON TIME',
  String shortStatus = 'OT',
  String tripId = '',
  int positionTimeSeconds = 55500,
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
    busLon: lon,
    heading: '90',
    speed: 20,
    positionTime: '',
    positionTimeSeconds: positionTimeSeconds,
    gtfsTripHeadsign: '',
    gtfsServiceId: '',
    gtfsStopSequenceStatus: status,
    gtfsStopSequenceMinsFromStop: 0,
    gtfsStopSequenceDeviation: '',
    gtfsStopSequenceClosestStop: '',
    gtfsStopSequenceSchedDifferenceMins: 0,
    gtfsTripId: tripId,
    shortStatus: shortStatus,
    departureTimeAtClosestStop: positionTimeSeconds,
  );
}

GtfsRepository _turnaroundRepo() {
  final repo = GtfsRepository();
  const outboundShape = 'shape-outbound';
  const inboundShape = 'shape-inbound';
  const routeId = 'route-3';

  repo.routesById[routeId] = const RouteInfo(
    routeId: routeId,
    routeShortName: '3',
    routeLongName: 'Route 3',
  );
  repo.tripsById['outbound'] = const TripInfo(
    tripId: 'outbound',
    routeId: routeId,
    serviceId: 'weekday',
    tripHeadsign: 'Stavanger Drive',
    directionId: 0,
    shapeId: outboundShape,
  );
  repo.tripsById['inbound'] = const TripInfo(
    tripId: 'inbound',
    routeId: routeId,
    serviceId: 'weekday',
    tripHeadsign: 'The Village',
    directionId: 1,
    shapeId: inboundShape,
  );

  repo.shapesById[outboundShape] = const [
    ShapePoint(
      shapeId: outboundShape,
      lat: 47.5600,
      lon: -52.7600,
      sequence: 1,
    ),
    ShapePoint(
      shapeId: outboundShape,
      lat: 47.5900,
      lon: -52.7350,
      sequence: 2,
    ),
    ShapePoint(
      shapeId: outboundShape,
      lat: 47.61842,
      lon: -52.71690,
      sequence: 3,
    ),
  ];
  repo.shapesById[inboundShape] = const [
    ShapePoint(
      shapeId: inboundShape,
      lat: 47.61842,
      lon: -52.71690,
      sequence: 1,
    ),
    ShapePoint(shapeId: inboundShape, lat: 47.5900, lon: -52.7350, sequence: 2),
    ShapePoint(shapeId: inboundShape, lat: 47.5600, lon: -52.7600, sequence: 3),
  ];
  repo.shapeCumulativeDistances[outboundShape] = _cumulative(
    repo.shapesById[outboundShape]!,
  );
  repo.shapeCumulativeDistances[inboundShape] = _cumulative(
    repo.shapesById[inboundShape]!,
  );
  return repo;
}

List<double> _cumulative(List<ShapePoint> points) {
  final result = <double>[0];
  for (var i = 1; i < points.length; i++) {
    result.add(
      result.last +
          NearestStopService.haversineDistance(
            points[i - 1].lat,
            points[i - 1].lon,
            points[i].lat,
            points[i].lon,
          ),
    );
  }
  return result;
}

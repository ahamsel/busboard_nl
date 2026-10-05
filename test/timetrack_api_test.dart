import 'dart:convert';

import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('prefers and combines GTFS-Realtime vehicle and trip data', () async {
    final measuredAt = DateTime.utc(2026, 7, 28, 18);
    final predictedAt = measuredAt.add(const Duration(minutes: 8));
    final positions = FeedMessage(
      header: FeedHeader(gtfsRealtimeVersion: '2.0'),
      entity: [
        FeedEntity(
          id: 'vehicle-0859',
          vehicle: VehiclePosition(
            trip: TripDescriptor(tripId: 'trip-20', routeId: '20'),
            position: Position(
              latitude: 47.53,
              longitude: -52.75,
              bearing: 90,
              speed: 10,
            ),
            currentStopSequence: 1,
            timestamp: Int64(measuredAt.millisecondsSinceEpoch ~/ 1000),
            vehicle: VehicleDescriptor(id: '0859'),
          ),
        ),
      ],
    );
    final updates = FeedMessage(
      header: FeedHeader(gtfsRealtimeVersion: '2.0'),
      entity: [
        FeedEntity(
          id: 'trip-20',
          tripUpdate: TripUpdate(
            trip: TripDescriptor(tripId: 'trip-20', routeId: '20'),
            vehicle: VehicleDescriptor(id: '0859'),
            stopTimeUpdate: [
              TripUpdate_StopTimeUpdate(
                stopSequence: 1,
                stopId: '1000',
                departure: TripUpdate_StopTimeEvent(
                  delay: 180,
                  time: Int64(predictedAt.millisecondsSinceEpoch ~/ 1000),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/vehiclepositions')) {
        return http.Response.bytes(positions.writeToBuffer(), 200);
      }
      if (request.url.path.endsWith('/tripupdates')) {
        return http.Response.bytes(updates.writeToBuffer(), 200);
      }
      if (request.url.queryParameters['type'] == 'routestatus') {
        return http.Response(
          jsonEncode([
            {
              'vehicle': '0859',
              'routeId': 20,
              'block': '20-1',
              'headsign': 'GALWAY',
              'stopName': 'Village Shopping Centre',
              'nearestStopName': 'Village Shopping Centre',
              'opStatus': 'BEHIND',
            },
          ]),
          200,
        );
      }
      return http.Response('', 404);
    });
    final api = TimeTrackApi(client: client);

    final result = await api.fetchVehiclesResult();

    expect(result.succeeded, isTrue);
    expect(result.source, LiveDataSource.gtfsRealtime);
    expect(result.vehicles, hasLength(1));
    final vehicle = result.vehicles.single;
    expect(vehicle.vehicle, '859');
    expect(vehicle.routeRun, 'Rt 20-1');
    expect(vehicle.routeNumber, 20);
    expect(vehicle.gtfsTripId, 'trip-20');
    expect(vehicle.gtfsTripHeadsign, 'GALWAY');
    // Metrobus currently publishes the Fleet View km/h value directly in the
    // GTFS-Realtime speed field.
    expect(vehicle.speed, closeTo(10, 0.01));
    expect(vehicle.gtfsStopSequenceSchedDifferenceMins, -3);
    expect(vehicle.gtfsStopSequenceStatus, 'BEHIND');
    expect(vehicle.departureTimeAtClosestStop, greaterThan(0));
  });

  test('uses Fleet View when GTFS-Realtime is unavailable', () async {
    final client = MockClient((request) async {
      if (request.url.queryParameters['type'] == 'routestatus') {
        return http.Response(
          jsonEncode([
            {
              'vehicle': '0963',
              'routeId': 9,
              'block': '09-1',
              'positionTime': '15:24:56',
              'headsign': 'MI - CNA - EAST WHITE HILLS',
              'stopName': 'Torbay Road Mall',
              'nearestStopName': 'Torbay Road Mall',
              'opStatus': 'BEHIND',
              'minsOffSchedule': 4,
              'latitude': 47.59,
              'longitude': -52.70,
              'speed': 18,
              'heading': 22,
            },
          ]),
          200,
        );
      }
      return http.Response('', 503);
    });
    final api = TimeTrackApi(client: client);

    final result = await api.fetchVehiclesResult();

    expect(result.source, LiveDataSource.fleetView);
    expect(result.vehicles.single.vehicle, '963');
    expect(result.vehicles.single.gtfsStopSequenceSchedDifferenceMins, -4);
  });

  Future<TimeTrackVehicle> fleetViewVehicle(String opStatus, int minsOffSchedule) async {
    final client = MockClient((request) async {
      if (request.url.queryParameters['type'] == 'routestatus') {
        return http.Response(
          jsonEncode([
            {
              'vehicle': '0963',
              'routeId': 9,
              'block': '09-1',
              'positionTime': '15:24:56',
              'headsign': 'MI - CNA - EAST WHITE HILLS',
              'stopName': 'Torbay Road Mall',
              'nearestStopName': 'Torbay Road Mall',
              'opStatus': opStatus,
              'minsOffSchedule': minsOffSchedule,
              'latitude': 47.59,
              'longitude': -52.70,
              'speed': 18,
              'heading': 22,
            },
          ]),
          200,
        );
      }
      return http.Response('', 503);
    });
    final result = await TimeTrackApi(client: client).fetchVehiclesResult();
    expect(result.source, LiveDataSource.fleetView);
    return result.vehicles.single;
  }

  test('Fleet View with no known status reports no delay, not on time', () async {
    for (final status in ['NO DATA', '', 'WEIRD']) {
      final v = await fleetViewVehicle(status, 7);
      expect(v.gtfsStopSequenceDeviation, '', reason: status);
      expect(v.deviation, '', reason: status);
      expect(v.shortStatus, '', reason: status);
      expect(v.gtfsStopSequenceSchedDifferenceMins, 0, reason: status);
    }
  });

  test('Fleet View keeps its delay for known statuses', () async {
    final early = await fleetViewVehicle('early', 3);
    expect(early.gtfsStopSequenceSchedDifferenceMins, 3);
    expect(early.gtfsStopSequenceDeviation, '3 MINS AHEAD');
    final late = await fleetViewVehicle('BEHIND', 4);
    expect(late.gtfsStopSequenceSchedDifferenceMins, -4);
    expect(late.gtfsStopSequenceDeviation, '4 MINS BEHIND');
    final onTime = await fleetViewVehicle('ON TIME', 0);
    expect(onTime.gtfsStopSequenceDeviation, 'ON TIME');
    expect(onTime.gtfsStopSequenceSchedDifferenceMins, 0);
  });

  test('uses legacy TimeTrack as the final fallback', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'www.metrobus.co.ca') {
        return http.Response(
          jsonEncode([
            {
              'routerun': 'Rt 6-1',
              'current_route': '06-1',
              'routenumber': 6,
              'vehicle': '0859',
              'bus_lat': 47.53,
              'bus_lon': -52.75,
              'gtfs_trip_id': 'trip-6',
            },
          ]),
          200,
        );
      }
      return http.Response('', 503);
    });
    final api = TimeTrackApi(client: client);

    final result = await api.fetchVehiclesResult();

    expect(result.source, LiveDataSource.legacyTimeTrack);
    expect(result.vehicles.single.vehicle, '859');
  });

  test('a valid empty GTFS-Realtime feed is not an error', () async {
    final emptyFeed = FeedMessage(
      header: FeedHeader(gtfsRealtimeVersion: '2.0'),
    );
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/vehiclepositions')) {
        return http.Response.bytes(emptyFeed.writeToBuffer(), 200);
      }
      return http.Response('', 503);
    });
    final api = TimeTrackApi(client: client);

    final result = await api.fetchVehiclesResult();

    expect(result.succeeded, isTrue);
    expect(result.source, LiveDataSource.gtfsRealtime);
    expect(result.vehicles, isEmpty);
  });
}

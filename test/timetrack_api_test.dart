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

  group('fetchLiveVehiclesResult (the alert watcher\'s lean check)', () {
    final measuredAt = DateTime.utc(2026, 7, 28, 18);
    final positions = FeedMessage(
      header: FeedHeader(gtfsRealtimeVersion: '2.0'),
      entity: [
        FeedEntity(
          id: 'vehicle-0859',
          vehicle: VehiclePosition(
            trip: TripDescriptor(tripId: 'trip-20', routeId: '20'),
            position: Position(latitude: 47.53, longitude: -52.75),
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
                departure: TripUpdate_StopTimeEvent(delay: 180),
              ),
            ],
          ),
        ),
      ],
    );

    MockClient recording(List<String> requested, {int positionsStatus = 200}) => MockClient((request) async {
          requested.add(request.url.toString());
          if (request.url.path.endsWith('/vehiclepositions')) {
            return positionsStatus == 200
                ? http.Response.bytes(positions.writeToBuffer(), 200)
                : http.Response('', positionsStatus);
          }
          if (request.url.path.endsWith('/tripupdates')) {
            return http.Response.bytes(updates.writeToBuffer(), 200);
          }
          return http.Response('', 403);
        });

    test('requests exactly the two GTFS-RT feeds', () async {
      final requested = <String>[];
      final api = TimeTrackApi(client: recording(requested));

      final result = await api.fetchLiveVehiclesResult();

      expect(result.succeeded, isTrue);
      expect(result.source, LiveDataSource.gtfsRealtime);
      expect(requested, unorderedEquals([
        'https://www.mbusapi.ca/gtfsrt/vehiclepositions',
        'https://www.mbusapi.ca/gtfsrt/tripupdates',
      ]));
    });

    test('fails when positions fail, without falling back to any other feed', () async {
      final requested = <String>[];
      final api = TimeTrackApi(client: recording(requested, positionsStatus: 503));

      final result = await api.fetchLiveVehiclesResult();

      expect(result.succeeded, isFalse);
      expect(result.vehicles, isEmpty);
      expect(requested.where((u) => u.contains('metrobus')), isEmpty);
      expect(requested.where((u) => !u.contains('/gtfsrt/')), isEmpty);
    });

    test('a vehicle carries the same schedule difference as the full call', () async {
      final lean = await TimeTrackApi(client: recording([])).fetchLiveVehiclesResult();
      final full = await TimeTrackApi(client: recording([])).fetchVehiclesResult();

      expect(lean.vehicles.single.gtfsStopSequenceSchedDifferenceMins, -3);
      expect(lean.vehicles.single.gtfsStopSequenceSchedDifferenceMins,
          full.vehicles.single.gtfsStopSequenceSchedDifferenceMins);
      expect(lean.vehicles.single.gtfsTripId, 'trip-20');
      expect(lean.vehicles.single.gtfsStopSequenceDeviation, full.vehicles.single.gtfsStopSequenceDeviation);
    });

    test('carries each trip\'s per-stop times from the trip-updates feed', () async {
      Int64 epoch(DateTime t) => Int64(t.millisecondsSinceEpoch ~/ 1000);
      final at = DateTime.utc(2026, 7, 28, 18, 10);
      final perStop = FeedMessage(
        header: FeedHeader(gtfsRealtimeVersion: '2.0'),
        entity: [
          FeedEntity(
            id: 'trip-20',
            tripUpdate: TripUpdate(
              trip: TripDescriptor(tripId: 'trip-20', routeId: '20'),
              stopTimeUpdate: [
                // Departure time beats arrival time.
                TripUpdate_StopTimeUpdate(
                  stopSequence: 1,
                  stopId: '1000',
                  arrival: TripUpdate_StopTimeEvent(delay: 120, time: epoch(at)),
                  departure: TripUpdate_StopTimeEvent(delay: 180, time: epoch(at.add(const Duration(minutes: 1)))),
                ),
                // Arrival only.
                TripUpdate_StopTimeUpdate(
                  stopSequence: 2,
                  stopId: '1001',
                  arrival: TripUpdate_StopTimeEvent(time: epoch(at.add(const Duration(minutes: 4)))),
                ),
                // A delay and no time.
                TripUpdate_StopTimeUpdate(
                  stopSequence: 3,
                  stopId: '1002',
                  departure: TripUpdate_StopTimeEvent(delay: 240),
                ),
                // Time and delay come from the same event: the departure has a time and no delay.
                TripUpdate_StopTimeUpdate(
                  stopSequence: 4,
                  stopId: '1003',
                  arrival: TripUpdate_StopTimeEvent(delay: 60, time: epoch(at.add(const Duration(minutes: 6)))),
                  departure: TripUpdate_StopTimeEvent(time: epoch(at.add(const Duration(minutes: 7)))),
                ),
                // The same stop again, later on the trip (a loop).
                TripUpdate_StopTimeUpdate(
                  stopSequence: 9,
                  stopId: '1000',
                  departure: TripUpdate_StopTimeEvent(delay: 60, time: epoch(at.add(const Duration(minutes: 30)))),
                ),
              ],
            ),
          ),
        ],
      );
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/vehiclepositions')) return http.Response.bytes(positions.writeToBuffer(), 200);
        if (request.url.path.endsWith('/tripupdates')) return http.Response.bytes(perStop.writeToBuffer(), 200);
        return http.Response('', 403);
      });

      final result = await TimeTrackApi(client: client).fetchLiveVehiclesResult();

      final trip = result.stopTimes['trip-20']!;
      expect(trip.keys, unorderedEquals(['1000', '1001', '1002', '1003']));
      expect(trip['1003']!.single.time, at.add(const Duration(minutes: 7)).toLocal());
      expect(trip['1003']!.single.delay, isNull, reason: 'not the arrival\'s delay');
      final first = trip['1000']!;
      expect(first, hasLength(2), reason: 'both visits, in feed order');
      expect(first[0].time, at.add(const Duration(minutes: 1)).toLocal());
      expect(first[0].delay, const Duration(seconds: 180));
      expect(first[1].time, at.add(const Duration(minutes: 30)).toLocal());
      expect(trip['1001']!.single.time, at.add(const Duration(minutes: 4)).toLocal());
      expect(trip['1001']!.single.delay, isNull);
      expect(trip['1002']!.single.time, isNull);
      expect(trip['1002']!.single.delay, const Duration(seconds: 240));
      final scheduled = DateTime(2026, 7, 28, 15, 0);
      expect(trip['1002']!.single.predictedFor(scheduled), scheduled.add(const Duration(minutes: 4)));
      expect(first[0].predictedFor(scheduled), first[0].time, reason: 'a time wins over the delay');
    });

    test('the Board\'s full call carries no per-stop times, as before', () async {
      final full = await TimeTrackApi(client: recording([])).fetchVehiclesResult();
      expect(full.stopTimes, isEmpty);
      expect(const TimeTrackFetchResult.failure(error: 'down').stopTimes, isEmpty);
    });
  });

  group('trip index (the Board links each trip to one bus)', () {
    TimeTrackVehicle vehicle(String id, {required String positionTime, required int seconds, String trip = '262921'}) =>
        TimeTrackVehicle.fromJson({
          'vehicle': id,
          'routeNumber': 18,
          'routeRun': 'Rt 18',
          'busLat': 47.5,
          'busLon': -52.7,
          'positionTime': positionTime,
          'positionTimeSeconds': seconds,
          'gtfsTripId': trip,
        });

    // The diagnosis' ghost: 1629 froze at 09:13:05 but kept reporting the
    // trip bus 1311 was really running, and came after it in every poll.
    final now = DateTime(2026, 10, 5, 9, 30);
    final real = vehicle('1311', positionTime: '2026-10-05T09:29:55.000', seconds: 9 * 3600 + 29 * 60 + 55);
    final ghost = vehicle('1629', positionTime: '2026-10-05T09:13:05.000', seconds: 9 * 3600 + 13 * 60 + 5);

    test('a frozen ghost on the same trip never beats the bus that is reporting', () {
      expect(TimeTrackApi.buildTripIndex([real, ghost], now: now)['262921']!.vehicle, '1311');
      expect(TimeTrackApi.buildTripIndex([ghost, real], now: now)['262921']!.vehicle, '1311');
    });

    test('without a full timestamp the age wraps at midnight', () {
      // Fleet View style clock times: 30 s after midnight beats 23:40.
      final justNow = vehicle('1311', positionTime: '00:00:30', seconds: 30);
      final old = vehicle('1629', positionTime: '23:40:00', seconds: 23 * 3600 + 40 * 60);
      final atMidnight = DateTime(2026, 10, 5, 0, 1);
      expect(TimeTrackApi.buildTripIndex([justNow, old], now: atMidnight)['262921']!.vehicle, '1311');
      expect(TimeTrackApi.buildTripIndex([old, justNow], now: atMidnight)['262921']!.vehicle, '1311');
    });

    test('a bus alone on its trip is kept, and other trips are untouched', () {
      final index = TimeTrackApi.buildTripIndex([ghost, vehicle('2573', positionTime: '', seconds: 0, trip: '1')], now: now);
      expect(index['262921']!.vehicle, '1629');
      expect(index['1']!.vehicle, '2573');
    });
  });
}

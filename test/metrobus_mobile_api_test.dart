import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'uses kiosk JSON and preserves realtime versus scheduled rows',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.path, '/NextBus/fleetview.asp');
        expect(request.url.queryParameters['type'], 'timetrackjson');
        expect(request.url.queryParameters['stopid'], '2735');
        return http.Response('''
        {
          "realtimeAvailable": true,
          "staleSeconds": 0,
          "arrivals": [
            {
              "route": "10",
              "runNumber": "10-1",
              "tripId": "256402",
              "vehicle": "01311",
              "scheduledDepartureSeconds": 57784,
              "predictedDepartureSeconds": 57784,
              "secondsToDeparture": 0,
              "displayTime": "Soon",
              "delaySeconds": 0,
              "scheduleStatus": "scheduled",
              "confidenceLabel": "Scheduled",
              "isRealtime": false,
              "predictionSource": "scheduled",
              "direction": "AVALON MALL - KELSEY DRIVE"
            },
            {
              "route": "10",
              "runNumber": "10-4",
              "tripId": "256427",
              "vehicle": "1419",
              "scheduledDepartureSeconds": 58984,
              "predictedDepartureSeconds": 59202,
              "secondsToDeparture": 1200,
              "delaySeconds": 218,
              "confidenceLabel": "Live prediction",
              "isRealtime": true,
              "predictionSource": "realtime",
              "currentLocation": "Freshwater Rd at Keane Pl",
              "direction": "AVALON MALL - KELSEY DRIVE",
              "updatedAt": "2026-07-28T16:05:58"
            }
          ]
        }
      ''', 200);
      });
      final api = MetrobusMobileApi(client: client);

      final result = await api.fetchDeparturesResult('2735');
      final cached = await api.fetchDeparturesResult('2735');

      expect(requests, 1);
      expect(identical(result, cached), isTrue);
      expect(result.succeeded, isTrue);
      expect(result.source, MetrobusDepartureSource.timeTrackJson);
      expect(result.realtimeAvailable, isTrue);
      expect(result.departures, hasLength(2));

      final scheduled = result.departures.first;
      expect(scheduled.tripId, '256402');
      expect(scheduled.vehicle, '1311');
      expect(scheduled.scheduledTime, '4:03p');
      expect(scheduled.isRealtime, isFalse);
      expect(scheduled.isTracked, isFalse);
      expect(scheduled.confidenceLabel, 'Scheduled');

      final realtime = result.departures.last;
      expect(realtime.routeRun, '10-4');
      expect(realtime.predictedTime, '4:26p');
      expect(realtime.delaySeconds, 218);
      expect(realtime.isRealtime, isTrue);
      expect(realtime.currentLocation, 'Freshwater Rd at Keane Pl');
      expect(realtime.updatedAt, DateTime(2026, 7, 28, 16, 5, 58));
    },
  );

  test('does not scrape legacy HTML when structured JSON is invalid', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.path, '/NextBus/fleetview.asp');
      return http.Response('not-json', 200);
    });
    final api = MetrobusMobileApi(client: client);

    final result = await api.fetchDeparturesResult('1000');

    expect(requests, 1);
    expect(result.succeeded, isFalse);
    expect(result.source, isNull);
    expect(result.departures, isEmpty);
  });

  test('accepts 24-hour times in prediction compatibility parsing', () {
    expect(MetrobusDeparture.parseTimeToGtfs('25:10:30')?.totalSeconds, 90630);
  });
}

import 'dart:convert';

import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/service_alerts_api.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses, deduplicates, and scopes current Metrobus alerts', () async {
    final now = DateTime.utc(2026, 7, 28, 18);
    final feed = FeedMessage(
      header: FeedHeader(
        gtfsRealtimeVersion: '2.0',
        timestamp: Int64(now.millisecondsSinceEpoch ~/ 1000),
      ),
      entity: [
        _routeAlert('ALERT6', '3', now),
        _routeAlert('ALERT7', '10', now),
        FeedEntity(
          id: 'ALERT28',
          alert: Alert(
            activePeriod: [_activePeriod(now)],
            informedEntity: [EntitySelector(agencyId: 'MB', stopId: '3080')],
            cause: Alert_Cause.CONSTRUCTION,
            effect: Alert_Effect.NO_SERVICE,
            headerText: _text('Stop out of service'),
            descriptionText: _text(
              'Due to construction stop 3080 is out of service.',
            ),
          ),
        ),
      ],
    );
    final api = ServiceAlertsApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/servicealerts')) {
          return http.Response.bytes(feed.writeToBuffer(), 200);
        }
        if (request.url.queryParameters['type'] == 'status') {
          return http.Response(
            jsonEncode({
              'serviceOperating': true,
              'serviceId': '5',
              'day': 'Weekday',
              'message': 'Weekday service operating',
            }),
            200,
          );
        }
        return http.Response('', 404);
      }),
    );

    final updates = await api.fetchUpdates(now: now);

    expect(updates.alerts, hasLength(2));
    expect(updates.feedTimestamp, now.toLocal());
    expect(updates.serviceStatus?.serviceOperating, isTrue);
    expect(updates.serviceStatus?.day, 'Weekday');

    final detour = updates.alerts.singleWhere(
      (alert) => alert.effect == ServiceAlertEffect.detour,
    );
    expect(detour.sourceIds, {'ALERT6', 'ALERT7'});
    expect(detour.routeIds, {'3', '10'});
    expect(detour.appliesTo(routeIds: {'3'}, stopId: '1000'), isTrue);
    expect(detour.appliesTo(routeIds: {'2'}, stopId: '1000'), isFalse);

    final stopClosure = updates.alerts.singleWhere(
      (alert) => alert.effect == ServiceAlertEffect.noService,
    );
    expect(stopClosure.cause, ServiceAlertCause.construction);
    expect(stopClosure.appliesTo(routeIds: const {}, stopId: '3080'), isTrue);
    expect(stopClosure.appliesTo(routeIds: const {}, stopId: '1000'), isFalse);
  });

  test(
    'drops expired alerts and tolerates unavailable system status',
    () async {
      final now = DateTime.utc(2026, 7, 28, 18);
      final feed = FeedMessage(
        header: FeedHeader(gtfsRealtimeVersion: '2.0'),
        entity: [
          FeedEntity(
            id: 'expired',
            alert: Alert(
              activePeriod: [
                TimeRange(
                  start: Int64(
                    now
                            .subtract(const Duration(days: 2))
                            .millisecondsSinceEpoch ~/
                        1000,
                  ),
                  end: Int64(
                    now
                            .subtract(const Duration(days: 1))
                            .millisecondsSinceEpoch ~/
                        1000,
                  ),
                ),
              ],
              headerText: _text('Old alert'),
            ),
          ),
        ],
      );
      final api = ServiceAlertsApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/servicealerts')) {
            return http.Response.bytes(feed.writeToBuffer(), 200);
          }
          return http.Response('', 503);
        }),
      );

      final updates = await api.fetchUpdates(now: now);

      expect(updates.alerts, isEmpty);
      expect(updates.serviceStatus, isNull);
    },
  );
}

FeedEntity _routeAlert(String id, String routeId, DateTime now) {
  return FeedEntity(
    id: id,
    alert: Alert(
      activePeriod: [_activePeriod(now)],
      informedEntity: [EntitySelector(routeId: routeId)],
      effect: Alert_Effect.DETOUR,
      headerText: _text('Water Street Detour'),
      descriptionText: _text('Routes 3 and 10 are detoured from Water Street.'),
    ),
  );
}

TimeRange _activePeriod(DateTime now) {
  return TimeRange(
    start: Int64(
      now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
    ),
    end: Int64(now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000),
  );
}

TranslatedString _text(String value) {
  return TranslatedString(
    translation: [TranslatedString_Translation(text: value, language: 'en')],
  );
}

import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_tracker.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:flutter_test/flutter_test.dart';

final _a = ArrivalAlert(
  stopId: '1150',
  stopName: 'MUN Centre',
  routeShortName: '10',
  headsign: 'MUN-CNA-MI',
  tripId: 't1',
  scheduledAt: DateTime(2026, 10, 6, 8, 12),
  expectedAt: DateTime(2026, 10, 6, 8, 12),
  live: true,
  leadMinutes: 5,
  setAt: DateTime(2026, 10, 6, 8, 0),
);

AlertStep _step(AlertSource s, int m) => AlertStep(alert: _a, minutesAway: m, source: s, fire: false, finished: false);

void main() {
  test('live alert', () {
    final m = alertMessage(_a, source: AlertSource.live, minutesAway: 5, use24h: true);
    expect(m.title, 'Route 10 is about 5 min away');
    expect(m.body, 'MUN Centre (stop 1150)');
  });
  test('iPhone estimate, 12- and 24-hour', () {
    final m = alertMessage(_a,
        source: AlertSource.live, minutesAway: 5, estimateFrom: DateTime(2026, 10, 6, 8, 2), use24h: false);
    expect(m.title, 'Route 10 should be about 5 min away');
    expect(m.body, 'Estimate from 8:02 AM. Open BusBoard for the latest.');
    expect(
        alertMessage(_a, source: AlertSource.live, minutesAway: 5, estimateFrom: DateTime(2026, 10, 6, 16, 2), use24h: true)
            .body,
        'Estimate from 16:02. Open BusBoard for the latest.');
  });
  test('timetable and lost', () {
    for (final s in [AlertSource.timetable, AlertSource.lost]) {
      final m = alertMessage(_a, source: s, minutesAway: 3, use24h: true);
      expect(m.title, 'Route 10 is scheduled in about 3 min');
      expect(m.body, 'MUN Centre (stop 1150) · no live tracking for this trip');
    }
  });
  test('due now', () {
    expect(alertMessage(_a, source: AlertSource.live, minutesAway: 0, use24h: true).title, 'Route 10 is due now');
  });
  test('ongoing notification', () {
    expect(ongoingTitle(_a), 'Route 10 to MUN-CNA-MI');
    expect(ongoingText(_step(AlertSource.live, 12)), 'About 12 min · live');
    expect(ongoingText(_step(AlertSource.timetable, 12)), 'About 12 min · scheduled');
    expect(ongoingText(_step(AlertSource.lost, 12)), 'Live tracking lost · using the timetable · about 12 min');
    expect(ongoingText(_step(AlertSource.live, 0)), 'Due now');
  });
}

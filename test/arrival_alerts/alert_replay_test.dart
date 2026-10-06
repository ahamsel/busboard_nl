// test/arrival_alerts/alert_replay_test.dart
// ALERT_CAPTURE=test/fixtures/arrival_alerts/stop_1150_<date>.jsonl flutter test test/arrival_alerts/alert_replay_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_tracker.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final path = Platform.environment['ALERT_CAPTURE'];

  test('replayed alerts fire within ±1 min of real departure − lead (spec §1)', () async {
    final samples = <(DateTime, MetrobusDeparturesResult)>[];
    for (final line in File(path!).readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
      final j = jsonDecode(line) as Map<String, dynamic>;
      final body = j['body'] as String;
      final status = j['status'] as int? ?? 200;
      final api = MetrobusMobileApi(client: MockClient((_) async => http.Response(body, status == 0 ? 500 : status)));
      samples.add((DateTime.parse(j['t'] as String), await api.fetchDeparturesResult('1150', forceRefresh: true)));
    }

    DateTime? predictedAt(MetrobusDeparture d, DateTime t) {
      final g = d.predictedGtfsTime ?? d.scheduledGtfsTime;
      return g == null ? null : instantOfServiceTime(g, t);
    }

    // Real departure: the last realtime prediction for each trip.
    final real = <String, DateTime>{};
    for (final (t, r) in samples) {
      for (final d in r.departures.where((d) => d.isRealtime && d.tripId.isNotEmpty)) {
        final p = predictedAt(d, t);
        if (p != null) real[d.tripId] = p;
      }
    }

    const tracker = AlertTracker();
    final errors = <Duration>[];
    for (final trip in real.keys) {
      for (final lead in alertLeadChoices) {
        final start = samples.indexWhere((s) => s.$2.departures.any((d) {
              final p = d.tripId == trip && d.isRealtime ? predictedAt(d, s.$1) : null;
              return p != null && p.difference(s.$1) >= Duration(minutes: lead + 1);
            }));
        if (start < 0) continue;
        final (t0, r0) = samples[start];
        final d0 = r0.departures.firstWhere((d) => d.tripId == trip);
        var alert = ArrivalAlert(
          stopId: '1150',
          stopName: 'Stop',
          routeShortName: d0.routeShortName,
          headsign: d0.headsign,
          tripId: trip,
          routeRun: d0.routeRun,
          vehicle: d0.vehicle,
          scheduledAt: instantOfServiceTime(d0.scheduledGtfsTime!, t0),
          expectedAt: predictedAt(d0, t0)!,
          live: true,
          leadMinutes: lead,
          setAt: t0,
          lastSeenAt: t0,
        );
        for (final (t, r) in samples.skip(start + 1)) {
          final s = tracker.step(alert, r, t);
          alert = s.alert;
          if (s.fire) {
            errors.add(t.difference(real[trip]!.subtract(Duration(minutes: lead))));
            break;
          }
          if (s.finished) break;
        }
      }
    }

    expect(errors, isNotEmpty);
    final within = errors.where((e) => e.inSeconds.abs() <= 60).length / errors.length;
    final worstLate = errors.map((e) => e.inSeconds).reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print('alerts: ${errors.length}, within ±60 s: ${(within * 100).toStringAsFixed(1)}%, worst late: $worstLate s');
    expect(within, greaterThanOrEqualTo(0.9));
    expect(worstLate, lessThanOrEqualTo(180));
  }, skip: path == null ? 'set ALERT_CAPTURE to a capture made with tool/capture_stop_predictions.dart' : false);
}

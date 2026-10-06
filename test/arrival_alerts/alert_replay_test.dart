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

class ReplayResult {
  final List<Duration> errors;
  final int attempted;
  final int unfired;
  final int capturedEnded;
  final int skippedLate;
  final int ghosts;

  ReplayResult({
    required this.errors,
    required this.attempted,
    required this.unfired,
    required this.capturedEnded,
    required this.skippedLate,
    required this.ghosts,
  });
}

DateTime? predictedAt(MetrobusDeparture d, DateTime t) {
  final g = d.predictedGtfsTime ?? d.scheduledGtfsTime;
  return g == null ? null : instantOfServiceTime(g, t);
}

Future<ReplayResult> replayCapture(List<String> lines, String stopId) async {
  final samples = <(DateTime, MetrobusDeparturesResult)>[];
  for (final line in lines.where((l) => l.trim().isNotEmpty)) {
    final j = jsonDecode(line) as Map<String, dynamic>;
    final body = j['body'] as String;
    final status = j['status'] as int? ?? 200;
    final api = MetrobusMobileApi(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(body),
          status == 0 ? 500 : status,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    samples.add((DateTime.parse(j['t'] as String), await api.fetchDeparturesResult(stopId, forceRefresh: true)));
  }

  // Real departure (spec §5): the first sample where the trip's live prediction reaches zero,
  // else the first sample after its last live appearance (it left the predictions). A trip that
  // vanishes while still predicted more than 5 min out is a feed ghost and is not scored.
  final lastLive = <String, (int, DateTime)>{};
  final reachedZero = <String, DateTime>{};
  for (var i = 0; i < samples.length; i++) {
    final (t, r) = samples[i];
    for (final d in r.departures.where((d) => d.isRealtime && d.tripId.isNotEmpty)) {
      final p = predictedAt(d, t);
      if (p == null) continue;
      lastLive[d.tripId] = (i, p);
      if (!p.isAfter(t)) reachedZero.putIfAbsent(d.tripId, () => t);
    }
  }
  final real = <String, DateTime>{};
  var ghosts = 0;
  lastLive.forEach((trip, last) {
    final zero = reachedZero[trip];
    if (zero != null) {
      real[trip] = zero;
      return;
    }
    final (i, p) = last;
    if (i + 1 >= samples.length) return; // still live when the capture ended
    if (p.difference(samples[i].$1) > const Duration(minutes: 5)) {
      ghosts++;
      return;
    }
    real[trip] = samples[i + 1].$1;
  });

  const tracker = AlertTracker();
  final errors = <Duration>[];
  var unfired = 0;
  var capturedEnded = 0;
  var skippedLate = 0;

  for (final trip in real.keys) {
    for (final lead in alertLeadChoices) {
      final start = samples.indexWhere((s) => s.$2.departures.any((d) {
            final p = d.tripId == trip && d.isRealtime ? predictedAt(d, s.$1) : null;
            return p != null && p.difference(s.$1) >= Duration(minutes: lead + 1);
          }));
      if (start < 0) {
        skippedLate++;
        continue;
      }
      final (t0, r0) = samples[start];
      final d0 = r0.departures.firstWhere(
        (d) => d.tripId == trip && d.isRealtime && predictedAt(d, t0) != null,
      );
      var alert = ArrivalAlert(
        stopId: stopId,
        stopName: 'Stop',
        routeShortName: d0.routeShortName,
        headsign: d0.headsign,
        tripId: trip,
        routeRun: d0.routeRun,
        vehicle: d0.vehicle,
        scheduledAt: instantOfServiceTime(d0.scheduledGtfsTime ?? d0.predictedGtfsTime!, t0),
        expectedAt: predictedAt(d0, t0)!,
        live: true,
        leadMinutes: lead,
        setAt: t0,
        lastSeenAt: t0,
      );
      var fired = false;
      for (final (t, r) in samples.skip(start + 1)) {
        final s = tracker.step(alert, r, t);
        alert = s.alert;
        if (s.fire) {
          errors.add(t.difference(real[trip]!.subtract(Duration(minutes: lead))));
          fired = true;
          break;
        }
        if (s.finished) break;
      }
      if (!fired) {
        final target = real[trip]!.subtract(Duration(minutes: lead));
        if (target.isAfter(samples.last.$1)) {
          capturedEnded++;
        } else {
          unfired++;
        }
      }
    }
  }

  final attempted = errors.length + unfired;
  return ReplayResult(
    errors: errors,
    attempted: attempted,
    unfired: unfired,
    capturedEnded: capturedEnded,
    skippedLate: skippedLate,
    ghosts: ghosts,
  );
}

void main() {
  final path = Platform.environment['ALERT_CAPTURE'];

  test('replayed alerts fire within ±1 min of real departure − lead (spec §1)', () async {
    final lines = File(path!).readAsLinesSync();
    final result = await replayCapture(lines, '1150');

    expect(result.attempted, greaterThan(0));
    final within = result.errors.where((e) => e.inSeconds.abs() <= 60).length / result.attempted;
    final worstLate = result.errors.isEmpty ? 0 : result.errors.map((e) => e.inSeconds).reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print(
      'alerts: ${result.attempted}, fired: ${result.errors.length}, unfired: ${result.unfired}, '
      'within ±60 s: ${(within * 100).toStringAsFixed(1)}%, worst late: ${worstLate}s, '
      'ghost trips: ${result.ghosts}, set too late: ${result.skippedLate}, capture ended: ${result.capturedEnded}',
    );
    expect(within, greaterThanOrEqualTo(0.9));
    if (result.errors.isNotEmpty) {
      expect(worstLate, lessThanOrEqualTo(180));
    }
  }, skip: path == null ? 'set ALERT_CAPTURE to a capture made with tool/capture_stop_predictions.dart' : false);
}

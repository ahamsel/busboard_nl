// test/arrival_alerts/alert_replay_test.dart
// NOTE: targets Metrobus's stop endpoint, which answers 403 Forbidden since 2026-10-05; pending a GTFS-RT rework.
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

  test('synthetic fixture: trip reaches zero, leads 3 and 5 fire within ±60s', () async {
    // Build 18 JSONL lines starting 2026-10-06T08:00:00, 30s apart.
    // Trip: route 10, t1, 10-4, vehicle 1415, scheduled/predicted 08:08:00.
    // Samples 0–16 (08:00:00–08:08:00): trip is live.
    // Sample 17 (08:08:30): trip disappeared (reaches zero at sample 16).
    // Real departure: 08:08:00 (first sample where prediction is not after sample time).
    // Lead 10: set too late (8 min out < 11 min needed) → skippedLate=1.
    // Leads 3, 5: set at samples where bus is 4+, 6+ min out, fire at alert times.
    // Expected: attempted=2 (leads 3 and 5), unfired=0, skippedLate=1, all errors ±60s.
    final start = DateTime(2026, 10, 6, 8, 0, 0);
    final departureSeconds = 8 * 3600 + 8 * 60; // 08:08:00
    final lines = <String>[];

    // Samples 0–16: trip is live (30s apart, 08:00 through 08:08)
    for (var i = 0; i < 17; i++) {
      final sampleTime = start.add(Duration(seconds: i * 30));
      final body = jsonEncode({
        'arrivals': [
          {
            'route': '10',
            'trip_id': 't1',
            'runNumber': '10-4',
            'vehicle': '1415',
            'scheduledDepartureSeconds': departureSeconds,
            'predictedDepartureSeconds': departureSeconds, // Fixed at 08:08:00
            'isRealtime': true,
            'direction': 'MUN',
          }
        ]
      });
      lines.add(jsonEncode({'t': sampleTime.toIso8601String(), 'status': 200, 'body': body}));
    }

    // Sample 17: trip has disappeared
    final emptyTime = start.add(const Duration(minutes: 8, seconds: 30));
    lines.add(jsonEncode({
      't': emptyTime.toIso8601String(),
      'status': 200,
      'body': jsonEncode({'arrivals': []})
    }));

    final result = await replayCapture(lines, '1150');

    // ignore: avoid_print
    print(
      'synthetic: attempted=${result.attempted}, fired=${result.errors.length}, '
      'unfired=${result.unfired}, skippedLate=${result.skippedLate}',
    );
    expect(result.attempted, equals(2), reason: 'Leads 3 and 5 should fire; lead 10 too late');
    expect(result.unfired, equals(0), reason: 'Both alerts should fire before trip vanishes');
    expect(result.skippedLate, equals(1), reason: 'Lead 10: bus only 8 min out at sample 0');
    for (final error in result.errors) {
      expect(error.inSeconds.abs(), lessThanOrEqualTo(60), reason: 'All errors within ±60s');
    }
  });
}

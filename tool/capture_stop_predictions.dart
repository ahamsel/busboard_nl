// tool/capture_stop_predictions.dart
// NOTE: targets Metrobus's stop endpoint, which answers 403 Forbidden since 2026-10-05; pending a GTFS-RT rework.
// Records one stop's Metrobus stop predictions every 30 s, as JSON lines, for the alert replay test.
//   dart run tool/capture_stop_predictions.dart 1150 120 > test/fixtures/arrival_alerts/stop_1150_<date>.jsonl
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tool/capture_stop_predictions.dart <stopId> <minutes>');
    exit(64);
  }
  final stopId = args[0];
  final end = DateTime.now().add(Duration(minutes: int.parse(args[1])));
  final url = Uri.parse('https://www.metrobusmobile.com/NextBus/fleetview.asp').replace(queryParameters: {
    'type': 'timetrackjson',
    'stopid': stopId,
    'lookaheadMinutes': '120',
  });
  final client = http.Client();
  while (DateTime.now().isBefore(end)) {
    final t = DateTime.now();
    try {
      final r = await client.get(url).timeout(const Duration(seconds: 10));
      stdout.writeln(jsonEncode({'t': t.toIso8601String(), 'status': r.statusCode, 'body': r.body}));
    } catch (e) {
      stdout.writeln(jsonEncode({'t': t.toIso8601String(), 'status': 0, 'body': ''}));
      stderr.writeln('$t $e');
    }
    await Future<void>.delayed(const Duration(seconds: 30) - DateTime.now().difference(t));
  }
  client.close();
}

// tool/capture_gtfsrt_alerts.dart
// Records Metrobus's two GTFS-RT feeds every 30 s, as JSON lines, for the arrival-alert replay test.
//   dart run tool/capture_gtfsrt_alerts.dart --minutes 120 --out test/fixtures/timetrack/raw_gtfsrt_<date>.jsonl
//
// Each line is {"fetch_time": "<ISO UTC>", "vehicle_positions": <FeedMessage>, "trip_updates": <FeedMessage>}, the
// FeedMessages as proto3 JSON. A feed that fails is written as null and the recording carries on.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;

const _feeds = {
  'vehicle_positions': 'https://www.mbusapi.ca/gtfsrt/vehiclepositions',
  'trip_updates': 'https://www.mbusapi.ca/gtfsrt/tripupdates',
};
const _interval = Duration(seconds: 30);

Future<void> main(List<String> args) async {
  int? minutes;
  String? out;
  for (var i = 0; i + 1 < args.length; i += 2) {
    switch (args[i]) {
      case '--minutes':
        minutes = int.tryParse(args[i + 1]);
      case '--out':
        out = args[i + 1];
    }
  }
  if (minutes == null || minutes <= 0 || out == null || args.length != 4) {
    stderr.writeln('usage: dart run tool/capture_gtfsrt_alerts.dart --minutes <n> --out <path>');
    exit(64);
  }

  final file = File(out);
  await file.parent.create(recursive: true);
  final sink = file.openWrite(mode: FileMode.append);
  final client = http.Client();
  final end = DateTime.now().add(Duration(minutes: minutes));
  var polls = 0;
  try {
    while (DateTime.now().isBefore(end)) {
      final started = DateTime.now();
      final line = <String, Object?>{'fetch_time': started.toUtc().toIso8601String()};
      final counts = <String>[];
      final results = await Future.wait(_feeds.values.map((url) => _fetch(client, url)));
      for (final (i, key) in _feeds.keys.indexed) {
        final (feed, note) = results[i];
        line[key] = feed?.toProto3Json();
        counts.add('$key=${feed == null ? note : feed.entity.length}');
      }
      sink.writeln(jsonEncode(line));
      await sink.flush();
      stdout.writeln('${line['fetch_time']} #$polls ${counts.join(' ')}');
      polls++;
      final wait = _interval - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  } finally {
    client.close();
    await sink.close();
  }
}

/// One feed as a FeedMessage, or null with a short reason.
Future<(FeedMessage?, String)> _fetch(http.Client client, String url) async {
  try {
    final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return (null, 'HTTP ${r.statusCode}');
    return (FeedMessage.fromBuffer(r.bodyBytes), '');
  } catch (e) {
    stderr.writeln('$url: $e');
    return (null, 'error');
  }
}

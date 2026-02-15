import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

void main(List<String> args) async {
  final config = _parseArgs(args);
  final outFile = File(config.outPath);
  await outFile.parent.create(recursive: true);

  final client = http.Client();
  final frames = <Map<String, dynamic>>[];
  final startedAt = DateTime.now().toUtc();
  final endAt = startedAt.add(Duration(seconds: config.durationSeconds));

  stdout.writeln(
    '[Capture] url=${config.url} interval=${config.intervalSeconds}s '
    'duration=${config.durationSeconds}s out=${outFile.path}',
  );

  var index = 0;
  while (DateTime.now().toUtc().isBefore(endAt)) {
    final fetchTime = DateTime.now().toUtc();
    Map<String, dynamic> frame;

    try {
      final response = await client
          .get(Uri.parse(config.url))
          .timeout(const Duration(seconds: 12));

      final vehicles = _decodeVehicles(response.body);
      frame = {
        'fetch_time': fetchTime.toIso8601String(),
        'status_code': response.statusCode,
        'vehicles': vehicles,
      };
      stdout.writeln(
        '[Capture] #$index status=${response.statusCode} vehicles=${vehicles.length}',
      );
    } catch (e) {
      frame = {
        'fetch_time': fetchTime.toIso8601String(),
        'status_code': -1,
        'vehicles': <Map<String, dynamic>>[],
        'error': e.toString(),
      };
      stdout.writeln('[Capture] #$index error=$e');
    }

    frames.add(frame);
    index++;

    final elapsed = DateTime.now().toUtc().difference(fetchTime);
    final wait = Duration(seconds: config.intervalSeconds) - elapsed;
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
  }

  final payload = {
    'captured_at': startedAt.toIso8601String(),
    'source_url': config.url,
    'interval_seconds': config.intervalSeconds,
    'duration_seconds': config.durationSeconds,
    'frames': frames,
  };

  final encoder = const JsonEncoder.withIndent('  ');
  await outFile.writeAsString(encoder.convert(payload));
  client.close();

  stdout.writeln('[Capture] wrote ${frames.length} frames to ${outFile.path}');
}

class _CaptureConfig {
  final String url;
  final int intervalSeconds;
  final int durationSeconds;
  final String outPath;

  const _CaptureConfig({
    required this.url,
    required this.intervalSeconds,
    required this.durationSeconds,
    required this.outPath,
  });
}

_CaptureConfig _parseArgs(List<String> args) {
  String url = 'https://www.metrobus.co.ca/api/timetrack/json/';
  var intervalSeconds = 5;
  var durationSeconds = 300;
  var outPath = 'test/fixtures/timetrack/capture.json';

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--url' && i + 1 < args.length) {
      url = args[++i];
      continue;
    }
    if (arg == '--interval' && i + 1 < args.length) {
      intervalSeconds = int.tryParse(args[++i]) ?? intervalSeconds;
      continue;
    }
    if (arg == '--duration' && i + 1 < args.length) {
      durationSeconds = int.tryParse(args[++i]) ?? durationSeconds;
      continue;
    }
    if (arg == '--out' && i + 1 < args.length) {
      outPath = args[++i];
      continue;
    }
    if (arg == '--help' || arg == '-h') {
      _printUsageAndExit();
    }
  }

  if (intervalSeconds < 1) intervalSeconds = 1;
  if (durationSeconds < intervalSeconds) durationSeconds = intervalSeconds;

  return _CaptureConfig(
    url: url,
    intervalSeconds: intervalSeconds,
    durationSeconds: durationSeconds,
    outPath: outPath,
  );
}

Never _printUsageAndExit() {
  stdout.writeln('Usage:');
  stdout.writeln(
    '  dart run tool/capture_timetrack_snapshots.dart '
    '[--url <endpoint>] [--interval <seconds>] [--duration <seconds>] '
    '[--out <path>]',
  );
  exit(0);
}

List<Map<String, dynamic>> _decodeVehicles(String body) {
  for (final candidate in _decodeCandidates(body)) {
    final decoded = _tryDecode(candidate);
    final extracted = _extractVehicleList(decoded);
    if (extracted != null) {
      return extracted
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final firstArray = candidate.indexOf('[');
    final lastArray = candidate.lastIndexOf(']');
    if (firstArray == -1 || lastArray == -1 || lastArray <= firstArray) {
      continue;
    }

    final sliced = candidate.substring(firstArray, lastArray + 1);
    final slicedDecoded = _tryDecode(sliced);
    final slicedExtracted = _extractVehicleList(slicedDecoded);
    if (slicedExtracted != null) {
      return slicedExtracted
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  }

  return const <Map<String, dynamic>>[];
}

Iterable<String> _decodeCandidates(String body) sync* {
  yield body;
  final sanitized = _sanitizeJsonText(body);
  if (sanitized != body) {
    yield sanitized;
  }
}

dynamic _tryDecode(String input) {
  try {
    return jsonDecode(input);
  } catch (_) {
    return null;
  }
}

List<dynamic>? _extractVehicleList(dynamic decoded) {
  if (decoded is List<dynamic>) return decoded;
  if (decoded is Map<String, dynamic>) {
    for (final key in const ['vehicles', 'data', 'results', 'items']) {
      final value = decoded[key];
      if (value is List<dynamic>) return value;
    }
  }
  return null;
}

String _sanitizeJsonText(String input) {
  return input.replaceAll(RegExp(r'[\u0000-\u001F]'), ' ');
}

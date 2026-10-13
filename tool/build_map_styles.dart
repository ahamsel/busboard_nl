/// Regenerates assets/map/harbour_{light,dark}.json from OpenFreeMap's
/// Positron style (spec §3.1). Run when OpenFreeMap changes its style:
///
///   dart run tool/build_map_styles.dart
///
/// To repaint the committed styles in a new palette without fetching (the
/// transform is idempotent, so only the colours change):
///
///   dart run tool/build_map_styles.dart --recolour
library;

import 'dart:convert';
import 'dart:io';

import 'src/harbour_style.dart';

const upstreamUrl = 'https://tiles.openfreemap.org/styles/positron';

const _targets = [
  ('assets/map/harbour_light.json', HarbourPalette.light),
  ('assets/map/harbour_dark.json', HarbourPalette.dark),
];

Future<void> main(List<String> args) async {
  if (args.contains('--recolour')) {
    for (final (path, palette) in _targets) {
      final file = File(path);
      final committed = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      file.writeAsStringSync(encodeHarbourStyle(buildHarbourStyle(committed, palette)));
      stdout.writeln('recoloured $path');
    }
    return;
  }
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(upstreamUrl))).close();
    if (response.statusCode != 200) {
      stderr.writeln('GET $upstreamUrl → ${response.statusCode}');
      exitCode = 1;
      return;
    }
    final upstream = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
    for (final (path, palette) in _targets) {
      final file = File(path)..createSync(recursive: true);
      file.writeAsStringSync(encodeHarbourStyle(buildHarbourStyle(upstream, palette)));
      stdout.writeln('wrote $path');
    }
  } finally {
    client.close();
  }
}

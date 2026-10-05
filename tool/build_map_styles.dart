/// Regenerates assets/map/harbour_{light,dark}.json from OpenFreeMap's
/// Positron style (spec §3.1). Run when OpenFreeMap changes its style:
///
///   dart run tool/build_map_styles.dart
library;

import 'dart:convert';
import 'dart:io';

import 'src/harbour_style.dart';

const upstreamUrl = 'https://tiles.openfreemap.org/styles/positron';

Future<void> main() async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(upstreamUrl))).close();
    if (response.statusCode != 200) {
      stderr.writeln('GET $upstreamUrl → ${response.statusCode}');
      exitCode = 1;
      return;
    }
    final upstream = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
    for (final (path, palette) in [
      ('assets/map/harbour_light.json', HarbourPalette.light),
      ('assets/map/harbour_dark.json', HarbourPalette.dark),
    ]) {
      final file = File(path)..createSync(recursive: true);
      file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(buildHarbourStyle(upstream, palette))}\n');
      stdout.writeln('wrote $path');
    }
  } finally {
    client.close();
  }
}

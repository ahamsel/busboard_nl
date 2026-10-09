import 'dart:io';

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _all = <IconData>[
  BBIcons.board, BBIcons.boardFill, BBIcons.map, BBIcons.mapFill, BBIcons.alerts, BBIcons.alertsFill,
  BBIcons.settings, BBIcons.search, BBIcons.location, BBIcons.nearMe, BBIcons.chevronRight,
  BBIcons.chevronDown, BBIcons.close, BBIcons.check, BBIcons.refresh, BBIcons.bus, BBIcons.stop,
  BBIcons.filter, BBIcons.info, BBIcons.warning, BBIcons.noService, BBIcons.schedule, BBIcons.star,
  BBIcons.starOutline, BBIcons.theme, BBIcons.offline, BBIcons.error, BBIcons.back, BBIcons.history,
  BBIcons.update, BBIcons.pin, BBIcons.timer, BBIcons.download, BBIcons.palette, BBIcons.detour,
  BBIcons.reducedService, BBIcons.stopMoved, BBIcons.accessible, BBIcons.additionalService,
  BBIcons.checkCircle, BBIcons.locationOff, BBIcons.layers, BBIcons.add, BBIcons.remove,
  BBIcons.bell, BBIcons.bellFill, BBIcons.plan, BBIcons.planFill, BBIcons.swap, BBIcons.walk,
  BBIcons.calendar, BBIcons.more,
];

void main() {
  test('every BBIcons glyph comes from the vendored Phosphor fonts', () {
    for (final icon in _all) {
      expect(icon.fontFamily, anyOf('PhosphorRegular', 'PhosphorFill'), reason: 'codePoint ${icon.codePoint}');
      expect(icon.fontPackage, isNull, reason: 'codePoint ${icon.codePoint}');
    }
  });

  testWidgets('pubspec declares both Phosphor font families', (tester) async {
    final manifest = await rootBundle.loadString('FontManifest.json');
    expect(manifest, contains('"family":"PhosphorRegular"'));
    expect(manifest, contains('"family":"PhosphorFill"'));
  });

  test('regular weight by default, fill weight for active states', () {
    expect(BBIcons.board.fontFamily, 'PhosphorRegular');
    expect(BBIcons.boardFill.fontFamily, 'PhosphorFill');
    expect(BBIcons.mapFill.fontFamily, 'PhosphorFill');
    expect(BBIcons.alertsFill.fontFamily, 'PhosphorFill');
    expect(BBIcons.plan.fontFamily, 'PhosphorRegular');
    expect(BBIcons.planFill.fontFamily, 'PhosphorFill');
    expect(BBIcons.star.fontFamily, 'PhosphorFill');
    expect(BBIcons.starOutline.fontFamily, 'PhosphorRegular');
  });

  test('no two BBIcons names share a glyph (except fill/regular pairs)', () {
    final regular = _all.where((i) => i.fontFamily == 'PhosphorRegular').map((i) => i.codePoint).toList();
    expect(regular.toSet().length, regular.length);
  });

  test('the kit no longer uses Material icon glyphs', () {
    final materialIcons = RegExp(r'(?<![A-Za-z_])Icons\.');
    final offenders = <String>[];
    for (final f in Directory('lib/ui/kit').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (materialIcons.hasMatch(src) || src.contains('show Icons')) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}

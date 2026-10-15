import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// The pixel at ([x], [y]) of the PNG at [path].
Future<ui.Color> _pixel(String path, int x, int y) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return ui.Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

/// Within 2 of [expected] on every channel (resizing may round).
Matcher _near(ui.Color expected) => predicate<ui.Color>(
      (c) => [(c.r, expected.r), (c.g, expected.g), (c.b, expected.b), (c.a, expected.a)]
          .every((p) => ((p.$1 - p.$2) * 255).abs() <= 2),
      'within 2/255 of $expected',
    );

const _blue = ui.Color(0xFF1272C9);

void main() {
  test('pubspec: the adaptive icon and both splashes use the Harbour blue (spec 2026-10-14 §2.5)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('adaptive_icon_background: "#1272C9"'));
    expect(RegExp(r'flutter_native_splash:\s*\n\s*color: "#1272C9"').hasMatch(pubspec), isTrue);
    expect(pubspec, contains('icon_background_color: "#1272C9"'));
    expect(pubspec, isNot(contains('#3FAE4F')), reason: 'the old green background is gone');
  });

  for (final svg in ['assets/brand/busboard_icon.svg', 'assets/brand/busboard_mark.svg']) {
    test('$svg: coral, gold, green and electric purple houses; ink #16181C; white bus and pin; centred', () {
      final text = File(svg).readAsStringSync().toUpperCase();
      for (final c in ['#EF5B5B', '#F2B53A', '#3FAE4F', '#B65CFF', '#16181C', '#FFFFFF']) {
        expect(text, contains(c));
      }
      // The blue house would vanish on the blue; the old violet and ink go with it.
      for (final old in ['#2F6FE4', '#8C5CF6', '#13261A']) {
        expect(text, isNot(contains(old)), reason: 'old colour $old');
      }
      expect(File(svg).readAsStringSync(), contains('transform="translate(2 2.5)"'), reason: 'the mark is centred');
    });
  }

  test('the icon master sits on the Harbour blue, not the old green', () {
    final icon = File('assets/brand/busboard_icon.svg').readAsStringSync();
    expect(icon, contains('<rect width="100" height="100" fill="#1272C9"/>'));
    expect(icon, isNot(contains('<rect width="100" height="100" fill="#3FAE4F"/>')));
  });

  test("the mark's view box is centred on the moved mark (its middle is 50, 50)", () {
    final box = RegExp(r'viewBox="([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)"')
        .firstMatch(File('assets/brand/busboard_mark.svg').readAsStringSync())!;
    final v = [for (var i = 1; i <= 4; i++) double.parse(box.group(i)!)];
    expect(v[0] + v[2] / 2, 50);
    expect(v[1] + v[3] / 2, 50);
  });

  testWidgets('the rendered icons and the iOS launch background are blue', (tester) async {
    await tester.runAsync(() async {
      expect(await _pixel('assets/icon/app_icon.png', 4, 4), _near(_blue));
      expect(await _pixel('assets/icon/app_icon_gplay.png', 2, 2), _near(_blue));
      expect(await _pixel('ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png', 0, 0), _near(_blue));
      expect(await _pixel('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png', 4, 4), _near(_blue));
    });
  });

  test('the generated Android resources carry the blue, and no green background is left', () {
    final colors = File('android/app/src/main/res/values/colors.xml').readAsStringSync().toUpperCase();
    expect(colors, contains('#1272C9'));
    expect(colors, isNot(contains('#3FAE4F')));
    for (final f in ['android/app/src/main/res/values-v31/styles.xml', 'android/app/src/main/res/values-night-v31/styles.xml']) {
      final xml = File(f).readAsStringSync().toUpperCase();
      expect(xml, contains('#1272C9'), reason: f);
      expect(xml, isNot(contains('#3FAE4F')), reason: f);
    }
  });
}

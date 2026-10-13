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

const _green = ui.Color(0xFF3FAE4F);

void main() {
  test('pubspec: the adaptive icon and both splashes use the brand green (spec §6.2)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('adaptive_icon_background: "#3FAE4F"'));
    expect(RegExp(r'flutter_native_splash:\s*\n\s*color: "#3FAE4F"').hasMatch(pubspec), isTrue);
    expect(pubspec, contains('icon_background_color: "#3FAE4F"'));
    expect(pubspec, isNot(contains('#3E7CB1')));
  });

  for (final svg in ['assets/brand/busboard_icon.svg', 'assets/brand/busboard_mark.svg']) {
    test('$svg: coral, gold, blue and violet houses; ink #13261A; white bus and pin (spec §6.1)', () {
      final text = File(svg).readAsStringSync().toUpperCase();
      for (final c in ['#EF5B5B', '#F2B53A', '#2F6FE4', '#8C5CF6', '#13261A', '#FFFFFF']) {
        expect(text, contains(c));
      }
      for (final old in ['#3E7CB1', '#D63B3B', '#F2C94C', '#C3A6EE', '#6FCF97', '#1C2A3A', '#F7F2EA']) {
        expect(text, isNot(contains(old)), reason: 'old colour $old');
      }
    });
  }

  test('the icon master sits on the brand green', () {
    expect(File('assets/brand/busboard_icon.svg').readAsStringSync(), contains('<rect width="100" height="100" fill="#3FAE4F"/>'));
  });

  testWidgets('the rendered icons and the iOS launch background are green', (tester) async {
    await tester.runAsync(() async {
      expect(await _pixel('assets/icon/app_icon.png', 4, 4), _near(_green));
      expect(await _pixel('assets/icon/app_icon_gplay.png', 2, 2), _near(_green));
      expect(await _pixel('ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png', 0, 0), _near(_green));
      expect(await _pixel('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png', 4, 4), _near(_green));
    });
  });

  test('the generated Android resources carry the green', () {
    expect(File('android/app/src/main/res/values/colors.xml').readAsStringSync().toUpperCase(), contains('#3FAE4F'));
    for (final f in ['android/app/src/main/res/values-v31/styles.xml', 'android/app/src/main/res/values-night-v31/styles.xml']) {
      final xml = File(f).readAsStringSync().toUpperCase();
      expect(xml, contains('#3FAE4F'), reason: f);
      expect(xml, isNot(contains('#3E7CB1')), reason: f);
    }
  });
}

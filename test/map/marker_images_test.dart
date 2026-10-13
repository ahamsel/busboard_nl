import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/marker_images.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit/kit_test_helpers.dart';

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

void _near(Color actual, Color expected) {
  int c(double v) => (v * 255).round();
  for (final (a, e) in [(actual.r, expected.r), (actual.g, expected.g), (actual.b, expected.b), (actual.a, expected.a)]) {
    expect((c(a) - c(e)).abs(), lessThanOrEqualTo(3), reason: 'got $actual, want $expected');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Real Figtree metrics, so badge widths match the app rather than Ahem.
  setUpAll(loadAppFonts);

  test('ids separate label, staleness, brightness and hue', () {
    expect(MarkerImages.badgeId('10', stale: false, brightness: Brightness.light), 'bb-badge-light-10');
    expect(MarkerImages.badgeId('10', stale: true, brightness: Brightness.dark), 'bb-badge-dark-stale-10');
    expect(MarkerImages.notchId(RouteHue.ocean, stale: false), 'bb-notch-ocean');
    expect(MarkerImages.notchId(RouteHue.ocean, stale: true), 'bb-notch-stale');
  });

  testWidgets('a badge is the route fill inside a white outline, at the pixel ratio', (tester) async {
    await tester.runAsync(() async {
      const pr = 2.0;
      final image = await _decode(await MarkerImages.badge(
        label: '10',
        hue: RouteHue.ocean,
        stale: false,
        brightness: Brightness.light,
        pixelRatio: pr,
      ));
      addTearDown(image.dispose);
      final size = MarkerImages.badgeSize('10');
      expect(image.width, (size.width * pr).ceil());
      expect(image.height, (size.height * pr).ceil());
      // Just inside the outline on the left edge, vertically centred: the fill.
      _near(await _pixel(image, ((MarkerImages.outline + 2) * pr).round(), image.height ~/ 2), RouteHue.ocean.fill);
      // On the outline at the top edge, horizontally centred: white.
      _near(await _pixel(image, image.width ~/ 2, (0.6 * pr).round()), const Color(0xFFFFFFFF));
      // The outer corner is rounded off, so the very corner is transparent.
      expect((await _pixel(image, 0, 0)).a, 0);
    });
  });

  testWidgets('a badge draws its number in ink inside the inner rect', (tester) async {
    await tester.runAsync(() async {
      final image = await _decode(await MarkerImages.badge(
          label: '10', hue: RouteHue.ocean, stale: false, brightness: Brightness.light, pixelRatio: 2));
      addTearDown(image.dispose);
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var inkPixels = 0;
      for (var y = image.height ~/ 3; y < image.height * 2 ~/ 3; y++) {
        for (var x = image.width ~/ 3; x < image.width * 2 ~/ 3; x++) {
          final i = (y * image.width + x) * 4;
          final dr = (data.getUint8(i) - (RoutePalette.ink.r * 255).round()).abs();
          final dg = (data.getUint8(i + 1) - (RoutePalette.ink.g * 255).round()).abs();
          final db = (data.getUint8(i + 2) - (RoutePalette.ink.b * 255).round()).abs();
          if (dr <= 12 && dg <= 12 && db <= 12 && data.getUint8(i + 3) > 240) inkPixels++;
        }
      }
      expect(inkPixels, greaterThan(0));
    });
  });

  testWidgets('a fractional pixel ratio still paints the whole PNG', (tester) async {
    await tester.runAsync(() async {
      const pr = 2.625;
      final image = await _decode(await MarkerImages.badge(
          label: '1', hue: RouteHue.ocean, stale: false, brightness: Brightness.light, pixelRatio: pr));
      addTearDown(image.dispose);
      expect(image.width, (30 * pr).ceil());
      // Last column, mid-height: still the white outline, not an unpainted gap.
      _near(await _pixel(image, image.width - 1, image.height ~/ 2), const Color(0xFFFFFFFF));
    });
  });

  testWidgets('a stale badge is grey, a dark badge uses the dark fill', (tester) async {
    await tester.runAsync(() async {
      final stale = await _decode(await MarkerImages.badge(
          label: '10', hue: RouteHue.ocean, stale: true, brightness: Brightness.light, pixelRatio: 1));
      addTearDown(stale.dispose);
      _near(await _pixel(stale, (MarkerImages.outline + 2).round(), stale.height ~/ 2), MarkerImages.staleFill);
      final dark = await _decode(await MarkerImages.badge(
          label: '10', hue: RouteHue.ocean, stale: false, brightness: Brightness.dark, pixelRatio: 1));
      addTearDown(dark.dispose);
      _near(await _pixel(dark, (MarkerImages.outline + 2).round(), dark.height ~/ 2), RouteHue.ocean.fillDark);
    });
  });

  test('longer labels make wider badges', () {
    expect(MarkerImages.badgeSize('10A').width, greaterThan(MarkerImages.badgeSize('1').width));
    expect(MarkerImages.badgeSize('1').width, MarkerImages.badgeMinWidth + 2 * MarkerImages.outline);
  });

  test('the notch base clears a badge at every heading', () {
    final clear = MarkerImages.notchBox / 2 - 10.5;
    for (final label in ['10A', '100']) {
      expect(clear, greaterThan(MarkerImages.badgeSize(label).width / 2 + 1), reason: label);
    }
    expect(clear, greaterThan(MarkerImages.badgeSize('10A').height / 2 + 1));
  });

  testWidgets('the notch points up from the top edge and leaves the centre clear', (tester) async {
    await tester.runAsync(() async {
      const pr = 2.0;
      final image = await _decode(await MarkerImages.notch(hue: RouteHue.ocean, stale: false, pixelRatio: pr));
      addTearDown(image.dispose);
      expect(image.width, (64 * pr).ceil());
      expect(image.height, image.width);
      _near(await _pixel(image, image.width ~/ 2, (6 * pr).round()), RouteHue.ocean.line);
      expect((await _pixel(image, image.width ~/ 2, image.height ~/ 2)).a, 0);
    });
  });

  testWidgets('your stop is a brand disc', (tester) async {
    await tester.runAsync(() async {
      final image = await _decode(await MarkerImages.myStop(brightness: Brightness.light, pixelRatio: 1));
      addTearDown(image.dispose);
      expect(image.width, MarkerImages.myStopSize.ceil());
      // Left of centre, inside the disc but outside the star: brand blue.
      _near(await _pixel(image, 5, image.height ~/ 2), BBColors.light.brand);
      // The centre is the star.
      _near(await _pixel(image, image.width ~/ 2, image.height ~/ 2), const Color(0xFFFFFFFF));
    });
  });

  testWidgets('a dark your-stop disc uses the dark brand', (tester) async {
    await tester.runAsync(() async {
      final image = await _decode(await MarkerImages.myStop(brightness: Brightness.dark, pixelRatio: 1));
      addTearDown(image.dispose);
      _near(await _pixel(image, 5, image.height ~/ 2), BBColors.dark.brand);
    });
  });
}

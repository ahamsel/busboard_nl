import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../kit/kit.dart';

/// Bitmaps the map draws (spec §3.2): one route badge per label (the board's
/// badge: radius 6.5, route fill, ink number, 2 px white outline), one heading
/// notch per hue, and your stop's brand disc with a white star. Rendered at
/// the device pixel ratio; MapLibre reads added images at the screen scale.
abstract final class MarkerImages {
  static const double badgeHeight = 22;
  static const double badgeMinWidth = 26;
  static const double outline = 2;
  static const double radius = 6.5;
  static const double fontSize = 12.5;

  /// Square box the notch is drawn in; its centre sits on the bus. The
  /// triangle's base is 21.5 px from the centre ([notchBox] / 2 - 10.5), which
  /// clears the half-width of a three-character badge (about 18.3 px, plus the
  /// outline) at east or west headings, and the half-height (14 px) at north
  /// and south.
  static const double notchBox = 64;
  static const double myStopSize = 26;
  static const String myStopId = 'bb-my-stop';

  static const Color staleFill = Color(0xFFC4CBD2);
  static const Color staleInk = Color(0xFF5A6674);
  static const Color staleNotch = Color(0xFF9AA4AE);
  static const Color _white = Color(0xFFFFFFFF);

  static String badgeId(String label, {required bool stale, required Brightness brightness}) =>
      'bb-badge-${brightness.name}-${stale ? 'stale-' : ''}$label';

  static String notchId(RouteHue hue, {required bool stale}) => 'bb-notch-${stale ? 'stale' : hue.name}';

  static TextPainter _label(String label, Color color) => TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontFamily: BBText.family, fontSize: fontSize, fontWeight: FontWeight.w800, color: color),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  static Size _sizeFor(TextPainter text) {
    final inner = math.max(badgeMinWidth, text.width + 10);
    return Size(inner + 2 * outline, badgeHeight + 2 * outline);
  }

  /// Logical size of a badge including its outline.
  static Size badgeSize(String label) {
    final text = _label(label, RoutePalette.ink);
    try {
      return _sizeFor(text);
    } finally {
      text.dispose();
    }
  }

  static Future<Uint8List> badge({
    required String label,
    required RouteHue hue,
    required bool stale,
    required Brightness brightness,
    required double pixelRatio,
  }) {
    final text = _label(label, stale ? staleInk : RoutePalette.ink);
    final size = _sizeFor(text);
    return _render(size, pixelRatio, (canvas) {
      final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(radius + outline));
      canvas.drawRRect(outer, Paint()..color = _white);
      final inner = RRect.fromRectAndRadius(
        Rect.fromLTWH(outline, outline, size.width - 2 * outline, badgeHeight),
        const Radius.circular(radius),
      );
      canvas.drawRRect(inner, Paint()..color = stale ? staleFill : hue.fillFor(brightness));
      text.paint(canvas, Offset((size.width - text.width) / 2, (size.height - text.height) / 2));
    }).whenComplete(text.dispose);
  }

  static Future<Uint8List> notch({
    required RouteHue hue,
    required bool stale,
    required Brightness brightness,
    required double pixelRatio,
  }) {
    const size = Size.square(notchBox);
    return _render(size, pixelRatio, (canvas) {
      const mid = notchBox / 2;
      final path = Path()
        ..moveTo(mid, 1.5)
        ..lineTo(mid + 6, 10.5)
        ..lineTo(mid - 6, 10.5)
        ..close();
      canvas.drawPath(path, Paint()..color = stale ? staleNotch : hue.lineFor(brightness));
      canvas.drawPath(
        path,
        Paint()
          ..color = _white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    });
  }

  static Future<Uint8List> myStop({required Brightness brightness, required double pixelRatio}) {
    const size = Size.square(myStopSize);
    final brand = brightness == Brightness.dark ? BBColors.dark.brand : BBColors.light.brand;
    return _render(size, pixelRatio, (canvas) {
      const c = Offset(myStopSize / 2, myStopSize / 2);
      canvas.drawCircle(c, myStopSize / 2, Paint()..color = _white);
      canvas.drawCircle(c, myStopSize / 2 - 2, Paint()..color = brand);
      canvas.drawPath(_star(c, 6.5, 2.8), Paint()..color = _white);
    });
  }

  static Path _star(Offset c, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static Future<Uint8List> _render(Size size, double pixelRatio, void Function(Canvas) draw) async {
    // Integer pixel size first, then scale by the exact ratio so a fractional
    // pixel ratio (such as 2.625) still paints every pixel of the PNG.
    final w = (size.width * pixelRatio).ceil();
    final h = (size.height * pixelRatio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(w / size.width, h / size.height);
    draw(canvas);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(w, h);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        return Uint8List.sublistView(bytes!);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }
}

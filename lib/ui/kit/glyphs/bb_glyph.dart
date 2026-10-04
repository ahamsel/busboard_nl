import 'package:flutter/widgets.dart';

enum BBGlyphKind { bus, stopPole, liveDot }

/// BusBoard's own glyphs, drawn in the B2 logo's soft style on a 24×24 grid.
/// Used like an icon (a size and a colour); the caller supplies the label,
/// and an unlabelled glyph is decorative.
class BBGlyph extends StatelessWidget {
  const BBGlyph(this.kind, {super.key, this.size = 24, required this.color, this.semanticLabel});

  final BBGlyphKind kind;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(kind, color)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: glyph);
    return Semantics(label: semanticLabel, image: true, child: glyph);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color);

  final BBGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    switch (kind) {
      case BBGlyphKind.bus:
        _bus(canvas, fill);
      case BBGlyphKind.stopPole:
        _stopPole(canvas, fill);
      case BBGlyphKind.liveDot:
        _liveDot(canvas, fill);
    }
  }

  // Front view: rounded body with a windshield cut out (even-odd keeps the
  // glyph one colour on any background), two wheels below.
  void _bus(Canvas canvas, Paint fill) {
    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromLTRBR(4, 3, 20, 18.5, const Radius.circular(3.5)))
      ..addRRect(RRect.fromLTRBR(6, 5.5, 18, 11, const Radius.circular(1.5)));
    canvas.drawPath(body, fill);
    canvas.drawRRect(RRect.fromLTRBR(5.5, 17.5, 8.5, 21, const Radius.circular(1.2)), fill);
    canvas.drawRRect(RRect.fromLTRBR(15.5, 17.5, 18.5, 21, const Radius.circular(1.2)), fill);
  }

  // A stop sign on a pole, as riders see it on the street.
  void _stopPole(Canvas canvas, Paint fill) {
    final sign = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromLTRBR(6, 2, 18, 11, const Radius.circular(2.5)))
      ..addRRect(RRect.fromLTRBR(9, 4.5, 15, 8.5, const Radius.circular(1)));
    canvas.drawPath(sign, fill);
    canvas.drawRRect(RRect.fromLTRBR(11, 11, 13, 21, const Radius.circular(1)), fill);
    canvas.drawRRect(RRect.fromLTRBR(8, 20, 16, 22, const Radius.circular(1)), fill);
  }

  // A solid dot inside a soft ring; never animated.
  void _liveDot(Canvas canvas, Paint fill) {
    canvas.drawCircle(const Offset(12, 12), 10, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(const Offset(12, 12), 5.5, fill);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind || old.color != color;
}

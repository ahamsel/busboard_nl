import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('a glyph renders at the requested size', (tester) async {
    await tester.pumpWidget(kitHost(const Center(
      child: BBGlyph(BBGlyphKind.bus, size: 20, color: Color(0xFF1C2A3A)),
    )));
    expect(tester.getSize(find.byType(BBGlyph)), const Size(20, 20));
  });

  testWidgets('unlabelled glyphs are hidden from screen readers; labelled ones are images', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const Column(children: [
      BBGlyph(BBGlyphKind.liveDot, color: Color(0xFF2E9E62)),
      BBGlyph(BBGlyphKind.stopPole, color: Color(0xFF1C2A3A), semanticLabel: 'Stop'),
    ])));
    expect(find.semantics.byLabel('Stop'), findsOneWidget);
    expect(tester.getSemantics(find.byType(BBGlyph).last), isSemantics(label: 'Stop', isImage: true));
    expect(
      find.semantics.byPredicate((n) => n.label.isEmpty && n.flagsCollection.isImage),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('every kind paints without errors in both themes', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(kitHost(
        Row(children: [for (final k in BBGlyphKind.values) BBGlyph(k, color: const Color(0xFF3E7CB1))]),
        brightness: b,
      ));
      expect(tester.takeException(), isNull);
    }
  });
}

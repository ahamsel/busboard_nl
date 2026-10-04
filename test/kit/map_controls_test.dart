import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('a chip is a labelled 44 pt button that taps', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(kitHost(Center(
      child: BBChip(label: 'MUN Centre · 1150', icon: BBIcons.star, chevron: true, onTap: () => taps++),
    )));
    expect(tester.getSize(find.byType(BBChip)).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(find.byType(BBChip)),
      isSemantics(label: 'MUN Centre · 1150', isButton: true, hasTapAction: true),
    );
    await tester.tap(find.byType(BBChip));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a selected chip uses the brand fill and says so', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(Center(child: BBChip(label: 'Route 10', selected: true, onTap: () {}))));
    final box = tester.widget<Container>(find.byKey(BBChip.surfaceKey)).decoration as BoxDecoration;
    expect(box.color, BBColors.light.brand);
    expect(tester.getSemantics(find.byType(BBChip)), isSemantics(label: 'Route 10', isSelected: true));
    handle.dispose();
  });

  testWidgets('a long chip label ellipsizes at 2x text on 320 pt', (tester) async {
    await tester.pumpWidget(kitHost(
      BBChip(label: 'Freshwater Rd before Anderson Ave · 3080', icon: BBIcons.star, chevron: true, onTap: () {}),
      width: 320,
      textScale: 2,
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BBChip)).width, lessThanOrEqualTo(320));
  });

  testWidgets('control pill buttons are 44 pt, labelled, and dim when disabled', (tester) async {
    final handle = tester.ensureSemantics();
    var located = 0;
    await tester.pumpWidget(kitHost(Center(
      child: BBControlPill(items: [
        BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: () => located++),
        const BBControlPillItem(icon: BBIcons.layers, semanticLabel: 'Layers', onPressed: null),
      ]),
    )));
    for (final button in tester.widgetList(find.byType(BBIconButton))) {
      expect(tester.getSize(find.byWidget(button)), const Size(44, 44));
    }
    expect(find.semantics.byLabel('My location'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('My location'));
    expect(located, 1);
    expect(tester.widget<Opacity>(find.descendant(of: find.byType(BBControlPill), matching: find.byType(Opacity)).last).opacity, 0.45);
    handle.dispose();
  });
}

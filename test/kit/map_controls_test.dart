import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/rendering.dart';
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
      find.semantics.byLabel('MUN Centre · 1150'),
      isSemantics(label: 'MUN Centre · 1150', isButton: true, hasTapAction: true),
    );
    await tester.tap(find.byType(BBChip));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a selected chip uses the brand fill and says so', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(Center(child: BBChip(label: 'Route 10', selected: true, onTap: () {}))));
    final box = tester.widget<AnimatedContainer>(find.byKey(BBChip.surfaceKey)).decoration as BoxDecoration;
    expect(box.color, BBColors.light.brand);
    expect(tester.getSemantics(find.byType(BBChip)), isSemantics(label: 'Route 10', isSelected: true));
    handle.dispose();
  });

  testWidgets('a selected chip carries a 1.5 px brandEdge border, on the map and on a sheet; unselected has none',
      (tester) async {
    BoxDecoration? edge() =>
        tester.widget<AnimatedContainer>(find.byKey(BBChip.surfaceKey)).foregroundDecoration as BoxDecoration?;
    for (final b in Brightness.values) {
      final t = b == Brightness.dark ? BBTokens.dark : BBTokens.light;
      for (final onSheet in [false, true]) {
        Widget chip(bool selected) {
          final c = Center(child: BBChip(label: 'Route 10', selected: selected, onTap: () {}));
          return kitHost(onSheet ? BBSurfaceScope(child: c) : c, brightness: b);
        }

        await tester.pumpWidget(chip(true));
        final border = edge()!.border! as Border;
        expect(border.top.color, t.brandEdge, reason: '${b.name} sheet=$onSheet');
        expect(border.top.width, 1.5, reason: '${b.name} sheet=$onSheet');
        await tester.pumpWidget(chip(false));
        await tester.pumpAndSettle();
        expect(edge(), isNull, reason: '${b.name} sheet=$onSheet unselected');
      }
    }
  });

  testWidgets('a long chip label ellipsizes at 2x text on 320 pt', (tester) async {
    const label = 'Freshwater Rd before Anderson Ave · 3080';
    await tester.pumpWidget(kitHost(
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: BBChip(label: label, icon: BBIcons.star, chevron: true, onTap: () {}),
        ),
      ),
      width: 390,
      textScale: 2,
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BBChip)).width, lessThanOrEqualTo(320));
    expect(tester.widget<Text>(find.text(label)).overflow, TextOverflow.ellipsis);
    expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isTrue);
  });

  testWidgets('an unselected chip is a plain button, not an unselected toggle', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(Center(child: BBChip(label: 'Route 10', onTap: () {}))));
    expect(
      find.semantics.byLabel('Route 10'),
      isSemantics(label: 'Route 10', isButton: true, hasSelectedState: false, isSelected: false),
    );
    handle.dispose();
  });

  testWidgets('an unselected control pill button is not an unselected toggle', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(Center(
      child: BBControlPill(items: [
        BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: () {}),
        BBControlPillItem(icon: BBIcons.layers, semanticLabel: 'Layers', onPressed: () {}, selected: true),
      ]),
    )));
    expect(find.semantics.byLabel('My location'), isSemantics(label: 'My location', hasSelectedState: false, isSelected: false));
    expect(find.semantics.byLabel('Layers'), isSemantics(label: 'Layers', hasSelectedState: true, isSelected: true));
    handle.dispose();
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

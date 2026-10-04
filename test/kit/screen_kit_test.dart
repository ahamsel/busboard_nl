import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('BBIconButton is a 44pt labelled button', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(kitHost(Center(child: BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () => taps++))));
    expect(tester.getSize(find.byType(BBIconButton)), const Size(44, 44));
    expect(tester.getSemantics(find.byType(BBIconButton)), isSemantics(label: 'Settings', isButton: true, hasTapAction: true));
    await tester.tap(find.byType(BBIconButton));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('BBTopBar shows title as a header, back and actions', (tester) async {
    final handle = tester.ensureSemantics();
    var back = 0;
    await tester.pumpWidget(kitHost(BBTopBar(
      title: 'Settings',
      subtitle: 'Stop #1150',
      onBack: () => back++,
      actions: [BBIconButton(icon: BBIcons.settings, semanticLabel: 'More', onPressed: () {})],
    )));
    expect(tester.getSemantics(find.text('Settings')), isSemantics(isHeader: true));
    expect(find.text('Stop #1150'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    expect(back, 1);
    handle.dispose();
  });

  testWidgets('BBEmptyState renders icon, title, message and action', (tester) async {
    await tester.pumpWidget(kitHost(BBEmptyState(
      icon: BBIcons.error,
      tone: BBEmptyTone.error,
      title: 'Failed to load schedule',
      message: 'boom',
      action: BBButton(label: 'Retry', onPressed: () {}),
    )));
    expect(find.text('Failed to load schedule'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.widget<Icon>(find.byType(Icon).first).color, BBColors.light.dangerInk);
  });

  testWidgets('BBLoading announces its label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const BBLoading(label: 'Finding nearby stops...')));
    expect(find.bySemanticsLabel('Finding nearby stops...'), findsWidgets);
    handle.dispose();
  });

  testWidgets('BBSectionHeader shows a count pill', (tester) async {
    await tester.pumpWidget(kitHost(const BBSectionHeader(title: 'Active now', count: 2, countTone: BBPillTone.danger)));
    expect(find.text('Active now'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('BBStepper steps within bounds and is adjustable for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    var value = 5;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => kitHost(BBStepper(
        value: value,
        min: 5,
        max: 60,
        step: 5,
        format: (v) => '$v seconds',
        semanticLabel: 'Refresh interval',
        onChanged: (v) => setState(() => value = v),
      )),
    ));
    expect(find.text('5 seconds'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Decrease Refresh interval'));
    await tester.pump();
    expect(value, 5); // at min: no change
    await tester.tap(find.bySemanticsLabel('Increase Refresh interval'));
    await tester.pump();
    expect(value, 10);
    final node = tester.getSemantics(find.bySemanticsLabel('Refresh interval'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
    expect(node.value, '10 seconds');
    handle.dispose();
  });

  testWidgets('screen-kit widgets do not overflow at text scale 2.0 on 320pt', (tester) async {
    await tester.pumpWidget(kitHost(
      Column(children: [
        BBTopBar(title: 'Choose a stop', subtitle: "Metrobus · St. John's", large: true,
            actions: [BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () {})]),
        BBStepper(value: 30, min: 5, max: 60, step: 5, format: (v) => '$v seconds', semanticLabel: 'Refresh interval', onChanged: (_) {}),
        const BBSectionHeader(title: 'Active now', count: 12),
      ]),
      textScale: 2.0,
      width: 320,
    ));
    expect(tester.takeException(), isNull);
  });
}

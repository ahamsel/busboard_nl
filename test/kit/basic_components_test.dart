import 'package:busboard_nl/ui/kit/bb_button.dart';
import 'package:busboard_nl/ui/kit/bb_card.dart';
import 'package:busboard_nl/ui/kit/bb_pill.dart';
import 'package:busboard_nl/ui/kit/bb_pressable.dart';
import 'package:busboard_nl/ui/kit/route_badge.dart';
import 'package:busboard_nl/ui/kit/route_palette.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Color? _boxColor(WidgetTester tester, Finder within) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: within, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('BBPressable taps, ignores taps when disabled, has no ink', (tester) async {
    var taps = 0;
    await tester.pumpWidget(kitHost(BBPressable(onTap: () => taps++, child: const Text('tap me'))));
    await tester.tap(find.text('tap me'));
    expect(taps, 1);
    expect(find.byType(InkWell), findsNothing);

    await tester.pumpWidget(kitHost(const BBPressable(onTap: null, child: Text('off'))));
    await tester.tap(find.text('off'));
    expect(taps, 1);
  });

  testWidgets('BBCard is tappable only when onTap is given', (tester) async {
    var taps = 0;
    await tester.pumpWidget(kitHost(BBCard(onTap: () => taps++, child: const Text('card'))));
    await tester.tap(find.text('card'));
    expect(taps, 1);
    expect(_boxColor(tester, find.byType(BBCard)), BBColors.light.surface);
  });

  testWidgets('BBButton primary uses brand fill; disabled does not fire', (tester) async {
    var taps = 0;
    await tester.pumpWidget(kitHost(BBButton(label: 'Use this stop', onPressed: () => taps++)));
    await tester.tap(find.text('Use this stop'));
    expect(taps, 1);
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(BBButton), matching: find.byType(Container)).first,
    );
    expect((container.decoration! as BoxDecoration).color, BBColors.light.brand);

    await tester.pumpWidget(kitHost(const BBButton(label: 'Disabled', onPressed: null)));
    await tester.tap(find.text('Disabled'));
    expect(taps, 1);
  });

  testWidgets('BBPill tones map to token colours', (tester) async {
    await tester.pumpWidget(kitHost(const BBPill(label: 'Detour', tone: BBPillTone.warn)));
    expect(find.text('Detour'), findsOneWidget);
    expect(_boxColor(tester, find.byType(BBPill)), BBColors.light.warnBg);

    await tester.pumpWidget(kitHost(const BBPill(label: 'Live', tone: BBPillTone.live, leadingDot: true)));
    expect(_boxColor(tester, find.byType(BBPill)), BBColors.light.liveSoft);
  });

  testWidgets('RouteBadge uses the route colour and announces the route', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const RouteBadge(routeNumber: 29)));
    expect(find.text('29'), findsOneWidget);
    expect(_boxColor(tester, find.byType(RouteBadge)), RoutePalette.of(29).fill);
    expect(find.bySemanticsLabel('Route 29'), findsOneWidget);

    await tester.pumpWidget(kitHost(const RouteBadge(routeNumber: 29), brightness: Brightness.dark));
    expect(_boxColor(tester, find.byType(RouteBadge)), RoutePalette.of(29).fillDark);
    handle.dispose();
  });

  testWidgets('large RouteBadge does not overflow at text scale 2.0', (tester) async {
    await tester.pumpWidget(kitHost(const RouteBadge(routeNumber: 26), textScale: 2.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('BBPressable does not stay pressed when disabled mid-press', (tester) async {
    double scaleOf() => tester.widget<AnimatedScale>(
          find.descendant(of: find.byType(BBPressable), matching: find.byType(AnimatedScale)),
        ).scale;

    await tester.pumpWidget(kitHost(BBPressable(onTap: () {}, child: const Text('hold'))));
    final gesture = await tester.startGesture(tester.getCenter(find.text('hold')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scaleOf(), 0.98);

    await tester.pumpWidget(kitHost(const BBPressable(onTap: null, child: Text('hold'))));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(), 1.0);
  });

  testWidgets('large RouteBadge grows with text scale, capped at 1.6x', (tester) async {
    await tester.pumpWidget(kitHost(const Center(child: RouteBadge(routeNumber: 26))));
    expect(tester.getSize(find.byType(RouteBadge)), const Size(40, 40));

    await tester.pumpWidget(kitHost(const Center(child: RouteBadge(routeNumber: 26)), textScale: 2.0));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(RouteBadge)), const Size(64, 64));
  });

  testWidgets('labelled pressable keeps its screen-reader tap action', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    const label = 'Route 29 Signal Hill Road, live, 4 minutes';
    await tester.pumpWidget(kitHost(BBCard(onTap: () => taps++, semanticLabel: label, child: const Text('row'))));
    expect(tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(label: label, isButton: true, hasTapAction: true));
    tester.semantics.tap(find.semantics.byLabel(label));
    await tester.pump();
    expect(taps, 1);

    // Disabled labelled pressable exposes no tap action.
    await tester.pumpWidget(kitHost(const BBPressable(onTap: null, semanticLabel: 'off', child: Text('x'))));
    expect(tester.getSemantics(find.bySemanticsLabel('off')),
        isSemantics(label: 'off', hasTapAction: false));
    handle.dispose();
  });
}

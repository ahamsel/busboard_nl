import 'package:busboard_nl/ui/kit/bb_pressable.dart';
import 'package:busboard_nl/ui/kit/bb_segmented.dart';
import 'package:busboard_nl/ui/kit/bb_switch.dart';
import 'package:busboard_nl/ui/kit/bb_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('BBSegmented reports the tapped value, ignores the selected one', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(kitHost(BBSegmented<String>(
      segments: const [BBSegment(value: 'near', label: 'Near me'), BBSegment(value: 'id', label: 'Stop number')],
      selected: 'near',
      onChanged: changes.add,
    )));
    await tester.tap(find.text('Stop number'));
    await tester.tap(find.text('Near me'));
    expect(changes, ['id']);
  });

  testWidgets('BBSegmented exposes selected state to accessibility', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(BBSegmented<int>(
      segments: const [BBSegment(value: 1, label: 'One'), BBSegment(value: 2, label: 'Two')],
      selected: 2,
      onChanged: (_) {},
    )));
    expect(tester.getSemantics(find.text('Two')), isSemantics(
      label: 'Two', isSelected: true, isButton: true, hasTapAction: true, isInMutuallyExclusiveGroup: true,
    ));
    handle.dispose();
  });

  testWidgets('BBSwitch toggles and announces state', (tester) async {
    final handle = tester.ensureSemantics();
    bool? got;
    await tester.pumpWidget(kitHost(BBSwitch(value: false, onChanged: (v) => got = v, semanticLabel: 'Haptics')));
    await tester.tap(find.byType(BBSwitch));
    expect(got, isTrue);
    expect(tester.getSemantics(find.byType(BBSwitch)), isSemantics(
      label: 'Haptics', hasToggledState: true, isToggled: false, hasTapAction: true,
    ));
    handle.dispose();
  });

  testWidgets('BBTextField shows hint and reports typing', (tester) async {
    final typed = <String>[];
    await tester.pumpWidget(kitHost(BBTextField(hint: 'Stop name or number on the pole', onChanged: typed.add)));
    expect(find.text('Stop name or number on the pole'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1150');
    expect(typed.last, '1150');
  });

  testWidgets('BBSegmented segments are at least 44 tall to tap', (tester) async {
    await tester.pumpWidget(kitHost(BBSegmented<String>(
      segments: const [BBSegment(value: 'near', label: 'Near me'), BBSegment(value: 'id', label: 'Stop number')],
      selected: 'near',
      onChanged: (_) {},
    )));
    final pressable = find.ancestor(of: find.text('Near me'), matching: find.byType(BBPressable));
    expect(tester.getSize(pressable).height, greaterThanOrEqualTo(44));
  });

  testWidgets('BBSegmented scales a pressed segment', (tester) async {
    await tester.pumpWidget(kitHost(BBSegmented<String>(
      segments: const [BBSegment(value: 'near', label: 'Near me'), BBSegment(value: 'id', label: 'Stop number')],
      selected: 'near',
      onChanged: (_) {},
    )));
    final g = await tester.startGesture(tester.getCenter(find.text('Stop number')));
    await tester.pump(const Duration(milliseconds: 200));
    final scale = tester.widget<AnimatedScale>(
      find.ancestor(of: find.text('Stop number'), matching: find.byType(AnimatedScale)).first,
    );
    expect(scale.scale, 0.98);
    await g.up();
  });

  testWidgets('BBSwitch hit area is at least 44x44', (tester) async {
    await tester.pumpWidget(kitHost(BBSwitch(value: false, onChanged: (_) {})));
    final size = tester.getSize(find.byType(BBSwitch));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('disabled BBSwitch ignores taps and reports disabled', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const BBSwitch(value: false, onChanged: null, semanticLabel: 'x')));
    await tester.tap(find.byType(BBSwitch));
    expect(tester.getSemantics(find.byType(BBSwitch)), isSemantics(label: 'x', isEnabled: false));
    handle.dispose();
  });
}

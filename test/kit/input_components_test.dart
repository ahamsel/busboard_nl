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
}

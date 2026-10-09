import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  test('BBThemeMode aliases ThemeMode so screens need not import Material', () {
    const BBThemeMode mode = BBThemeMode.dark;
    expect(mode, ThemeMode.dark);
  });

  test('new icons exist', () {
    for (final icon in [
      BBIcons.history, BBIcons.update, BBIcons.pin, BBIcons.timer, BBIcons.download, BBIcons.palette,
      BBIcons.detour, BBIcons.reducedService, BBIcons.stopMoved, BBIcons.accessible,
      BBIcons.additionalService, BBIcons.checkCircle, BBIcons.locationOff, BBIcons.layers,
      BBIcons.add, BBIcons.remove,
    ]) {
      expect(icon, isA<IconData>());
    }
  });

  testWidgets('BBPill wrap lets a long label wrap instead of ellipsising', (tester) async {
    const label = 'Freshwater Rd before Anderson Ave · 3080';
    await tester.pumpWidget(kitHost(const SizedBox(width: 160, child: BBPill(label: label, wrap: true)), width: 160));
    final text = tester.widget<Text>(find.text(label));
    expect(text.maxLines, isNull);
    expect(text.softWrap, isTrue);
    expect(text.overflow, TextOverflow.visible);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(kitHost(const SizedBox(width: 160, child: BBPill(label: label)), width: 160));
    expect(tester.widget<Text>(find.text(label)).overflow, TextOverflow.ellipsis);
  });

  testWidgets('BBButton wrap lets a long label wrap instead of ellipsising', (tester) async {
    const label = 'Plan a trip from here, please';
    await tester.pumpWidget(kitHost(
      SizedBox(width: 160, child: BBButton(label: label, wrap: true, expand: true, onPressed: () {})),
      width: 160,
    ));
    expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(kitHost(
      SizedBox(width: 160, child: BBButton(label: label, expand: true, onPressed: () {})),
      width: 160,
    ));
    expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isTrue);
  });

  testWidgets('BBTextField applies formatters and shows an error', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(kitHost(BBTextField(
      controller: controller,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
      errorText: 'Stop ID must be 4 digits',
      textAlign: TextAlign.center,
    )));
    await tester.enterText(find.byType(TextField), '12a345');
    expect(controller.text, '1234');
    expect(find.text('Stop ID must be 4 digits'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).textAlign, TextAlign.center);
  });

  testWidgets('BBTextField error is announced and the border turns danger', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const BBTextField(errorText: 'Please enter a stop ID')));
    expect(tester.getSemantics(find.text('Please enter a stop ID')), isSemantics(isLiveRegion: true));
    final box = tester.widget<Container>(find.descendant(of: find.byType(BBTextField), matching: find.byType(Container)).first);
    expect(((box.decoration! as BoxDecoration).border! as Border).top.color, BBColors.light.dangerInk);
    handle.dispose();
  });
}

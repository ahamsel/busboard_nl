import 'package:busboard_nl/app.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders with the Harbour theme', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BusboardApp()));
    await tester.pump(const Duration(milliseconds: 101));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.extension<BBTokens>(), isNotNull);
    expect(app.darkTheme!.extension<BBTokens>()!.isDark, isTrue);
  });
}

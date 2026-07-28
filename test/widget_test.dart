import 'package:flutter_test/flutter_test.dart';
import 'package:busboard_nl/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Just verify the app widget builds without error
    await tester.pumpWidget(const ProviderScope(child: BusboardApp()));
    await tester.pump(const Duration(milliseconds: 101));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

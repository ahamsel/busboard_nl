import 'dart:io';

import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:busboard_nl/ui/kit/bb_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('copy matches the spec verbatim', () {
    expect(LegalCopy.independence,
        'BusBoard NL is an independent app and is not affiliated with Metrobus Transit.');
    expect(LegalCopy.dataCredit, 'Schedules and live data: Metrobus open data (GTFS, GTFS-Realtime)');
    expect(LegalCopy.mapCredit, 'Map: OpenFreeMap · © OpenStreetMap contributors');
    expect(LegalCopy.footer, 'Data from Metrobus open data · BusBoard is independent');
  });

  test('no UI text claims to be official Metrobus', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => File(f.path).readAsStringSync().contains(RegExp(r"'[^']*Official Metrobus")))
        .map((f) => f.path)
        .toList();
    expect(hits, isEmpty);
  });

  testWidgets('Settings shows the independence line and credits', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: BBTheme.light(), home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(LegalCopy.independence), 200);
    expect(find.text(LegalCopy.independence), findsOneWidget);
    expect(find.text(LegalCopy.dataCredit), findsOneWidget);
    expect(find.text(LegalCopy.mapCredit), findsOneWidget);
  });
}

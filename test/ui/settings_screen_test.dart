import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {Future<GtfsRepository> Function()? gtfs, double textScale = 1, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  // Riverpod 3 retries failed providers with backoff (~38 s in total), which
  // would keep the refresh future pending; fail immediately in tests.
  final container = ProviderContainer(retry: (_, _) => null, overrides: [
    if (gtfs != null) gtfsRepositoryProvider.overrideWith((ref) => gtfs()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: BBTheme.light(),
      home: const SettingsScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('About shows the version the app was built as, not a typed-in one', (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'BusBoard NL', packageName: 'com.ahamsel.busboard_nl', version: '1.5.1', buildNumber: '13', buildSignature: '');
    await _pump(tester);
    await tester.scrollUntilVisible(find.textContaining('BusBoard NL v'), 200);
    expect(find.text('BusBoard NL v1.5.1'), findsOneWidget);
    expect(find.textContaining('v1.1.0'), findsNothing);
  });

  testWidgets('app theme segments write themeMode', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Dark').first);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, BBThemeMode.dark);
  });

  testWidgets('map theme: Match app / Light / Dark write mapThemeMode', (tester) async {
    final c = await _pump(tester);
    expect(find.text('Map theme'), findsOneWidget);
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).mapThemeMode, BBThemeMode.light);
    await tester.tap(find.text('Match app'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).mapThemeMode, isNull);
  });

  testWidgets('refresh interval stepper steps by 5 within 5–60', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await _pump(tester);
    expect(find.text('5 seconds'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Increase Refresh interval'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).refreshIntervalSeconds, 10);
    handle.dispose();
  });

  testWidgets('a failed schedule refresh re-enables the button and tells the user', (tester) async {
    // Settings does not watch the repository until Refresh is tapped, so the
    // first (and only) load is the refresh itself — make it fail.
    await _pump(tester, gtfs: () => Future<GtfsRepository>.error(Exception('offline')));
    await tester.scrollUntilVisible(find.text('Refresh schedule now'), 200);
    // scrollUntilVisible stops once the widget is built (inside the list's
    // cache extent), which can still be below the 600pt test viewport.
    await tester.ensureVisible(find.text('Refresh schedule now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh schedule now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Couldn't refresh schedule data. Try again later."), findsOneWidget);
    expect(find.text('Refresh schedule now'), findsOneWidget); // not stuck on "Downloading..."
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('no overflow at text scale 2.0 on 320pt, top to bottom', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
    // The list is lazy: scroll through all of it so every card gets laid out.
    final bottom = find.text(LegalCopy.mapCredit).hitTestable();
    var drags = 0;
    while (bottom.evaluate().isEmpty && drags++ < 40) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(bottom, findsOneWidget);
  });

  testWidgets('while refreshing the button reads Downloading... and is disabled', (tester) async {
    final never = Completer<GtfsRepository>();
    final c = await _pump(tester, gtfs: () => never.future);
    await tester.scrollUntilVisible(find.text('Refresh schedule now'), 200);
    await tester.ensureVisible(find.text('Refresh schedule now'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).forceGtfsRefresh, isFalse);
    await tester.tap(find.text('Refresh schedule now'));
    await tester.pump();
    expect(find.text('Downloading...'), findsOneWidget);
    expect(find.text('Refresh schedule now'), findsNothing);
    final button = tester.widget<BBButton>(find.ancestor(of: find.text('Downloading...'), matching: find.byType(BBButton)));
    expect(button.onPressed, isNull);
    expect(c.read(settingsProvider).forceGtfsRefresh, isTrue);
  });

  testWidgets('a successful refresh returns to Refresh schedule now with no toast', (tester) async {
    final c = await _pump(tester, gtfs: () async => GtfsRepository());
    await tester.scrollUntilVisible(find.text('Refresh schedule now'), 200);
    await tester.ensureVisible(find.text('Refresh schedule now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh schedule now'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh schedule now'), findsOneWidget);
    expect(find.text('Downloading...'), findsNothing);
    expect(find.text("Couldn't refresh schedule data. Try again later."), findsNothing);
    expect(c.read(settingsProvider).forceGtfsRefresh, isTrue);
  });

  testWidgets('a stored legacy ThemeMode.system map theme selects Match app', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, prefs: {'mapThemeMode': 0});
    expect(tester.getSemantics(find.bySemanticsLabel('Match app')), isSemantics(isSelected: true));
    handle.dispose();
  });

  testWidgets('an out-of-range stored interval shows 60 and cannot be increased', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, prefs: {'refreshInterval': 100});
    expect(find.text('60 seconds'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('Increase Refresh interval')), isSemantics(isEnabled: false));
    handle.dispose();
  });

  testWidgets('at the 60 s maximum, Increase leaves the value unchanged', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await _pump(tester, prefs: {'refreshInterval': 60});
    expect(find.text('60 seconds'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Increase Refresh interval'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).refreshIntervalSeconds, 60);
    expect(find.text('60 seconds'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the stored interval is clamped to 5..60 when loaded, so the board timer agrees with the display', (tester) async {
    final high = await _pump(tester, prefs: {'refreshInterval': 100});
    expect(high.read(settingsProvider).refreshIntervalSeconds, 60);
    final low = await _pump(tester, prefs: {'refreshInterval': 1});
    expect(low.read(settingsProvider).refreshIntervalSeconds, 5);
  });

  testWidgets("the schedule's last-updated time follows the device clock setting", (tester) async {
    await _pump(tester, prefs: {'lastGtfsUpdate': '2026-10-04T16:11:00.000'});
    expect(find.textContaining('Oct 4, 2026 4:11 PM', findRichText: true), findsOneWidget);
  });
}

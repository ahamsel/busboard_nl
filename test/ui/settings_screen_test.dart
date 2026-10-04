import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {Future<GtfsRepository> Function()? gtfs, double textScale = 1}) async {
  SharedPreferences.setMockInitialValues({});
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

  testWidgets('no overflow at text scale 2.0 on 320pt', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });
}

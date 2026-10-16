import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/routing/notification_route.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_board_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_screen.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:busboard_nl/ui/shell/app_shell.dart';
import 'package:busboard_nl/ui/shell/top_actions.dart';
import 'package:busboard_nl/ui/stop_picker/stop_picker_screen.dart';
import 'package:busboard_nl/ui/trip_planner/plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

ServiceAlert _alert(String header, {bool active = true}) => ServiceAlert(
      sourceIds: {header},
      header: header,
      description: '',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: active ? const [] : [ServiceAlertPeriod(start: DateTime(2099))],
      targets: const [],
    );

GoRouter _router(WidgetTester tester) => GoRouter.of(tester.element(find.byType(AppShell, skipOffstage: false)));

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(AppShell, skipOffstage: false)));

int _tab(WidgetTester tester) => tester.widget<BBNavBar>(find.byType(BBNavBar)).currentIndex;

/// The Map and Board pages started their refresh timers; let them run out after they go.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
}

void main() {
  final now = DateTime(testDay.year, testDay.month, testDay.day, 8, 1);
  const tabs = [('Board', '/', StopPickerScreen), ('Map', '/map', MapScreen)];
  const pages = [
    ('Plan', TopActions.planKey, PlanScreen),
    ('Alerts', TopActions.alertsKey, AlertsScreen),
    ('Settings', TopActions.settingsKey, SettingsScreen),
  ];

  testWidgets('the bar has two tabs, Board and Map', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    final bar = find.byType(BBNavBar);
    expect(tester.widget<BBNavBar>(bar).items.map((i) => i.label), ['Board', 'Map']);
    expect(find.descendant(of: bar, matching: find.text('Alerts')), findsNothing);
    expect(find.descendant(of: bar, matching: find.text('Plan')), findsNothing);
  });

  for (final (tabName, path, tabScreen) in tabs) {
    testWidgets('on the $tabName tab, Plan, Alerts and Settings sit top right in that order', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: path);
      final plan = tester.getRect(find.byKey(TopActions.planKey));
      final alerts = tester.getRect(find.byKey(TopActions.alertsKey));
      final settings = tester.getRect(find.byKey(TopActions.settingsKey));
      expect(plan.right, lessThanOrEqualTo(alerts.left));
      expect(alerts.right, lessThanOrEqualTo(settings.left));
      final screen = tester.getSize(find.byType(AppShell));
      expect(settings.right, greaterThan(screen.width - 24), reason: 'at the right edge');
      expect(settings.top, lessThan(screen.height / 4), reason: 'at the top');
      expect(find.byType(tabScreen), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('on the $tabName tab, each button is labelled and at least 44 pt', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: path,
          alerts: [_alert('Detour'), _alert('Closure'), _alert('Later', active: false)]);
      for (final (key, label) in [
        (TopActions.planKey, 'Plan a trip'),
        (TopActions.alertsKey, 'Service alerts, 2 active'),
        (TopActions.settingsKey, 'Settings'),
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(tester.getSemantics(find.byKey(key)), isSemantics(label: label, isButton: true, hasTapAction: true));
      }
      handle.dispose();
      await _unmount(tester);
    });

    for (final (pageName, key, page) in pages) {
      testWidgets('from the $tabName tab, $pageName opens as a page over the tabs, and back returns to $tabName',
          (tester) async {
        await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: path);
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget);
        expect(find.byType(BBNavBar), findsNothing, reason: 'a full-screen page, with no tab bar');
        await tester.tap(find.byIcon(BBIcons.back));
        await tester.pumpAndSettle();
        expect(find.byType(page), findsNothing);
        expect(find.byType(tabScreen), findsOneWidget);
        expect(_tab(tester), tabName == 'Board' ? 0 : 1);
        await _unmount(tester);
      });

      testWidgets('from the $tabName tab, Android back closes $pageName and returns to $tabName', (tester) async {
        await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: path);
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget);
        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(page), findsNothing);
        expect(find.byType(tabScreen), findsOneWidget);
        expect(_tab(tester), tabName == 'Board' ? 0 : 1);
        await _unmount(tester);
      });
    }
  }

  group('on a small phone at large text the buttons take a row of their own above the header', () {
    setUpAll(loadAppFonts);

    /// The text is laid out at its full width: not cut, ellipsised or broken inside a word.
    void readsInFull(WidgetTester tester, String text) {
      final p = tester.renderObject<RenderParagraph>(find.text(text));
      expect(p.size.width, greaterThanOrEqualTo(p.getMinIntrinsicWidth(double.infinity) - 0.5), reason: text);
      expect(p.didExceedMaxLines, isFalse, reason: text);
    }

    // 360 dp (the commonest Android width) and 375 pt (iPhone SE, 12 and 13 mini) keep one row at 1x, as 390 does.
    for (final (size, scale, stacked) in [
      (const Size(390, 844), 1.0, false),
      (const Size(375, 667), 1.0, false),
      (const Size(360, 780), 1.0, false),
      (const Size(320, 568), 2.0, true),
    ]) {
      final at = '${size.width.toInt()} pt, ${scale}x text';
      testWidgets('the stop picker at $at', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/', textScale: scale);
        final buttons = tester.getRect(find.byKey(TopActions.settingsKey));
        final title = tester.getRect(find.text('Choose a stop'));
        expect(buttons.bottom <= title.top, stacked, reason: stacked ? 'above the title' : 'beside the title');
        readsInFull(tester, 'Choose a stop');
        expect(tester.takeException(), isNull);
      });

      testWidgets('the Board at $at', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        // A four-digit stop number, as Metrobus's are: the widest pill the header has to fit.
        await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/board/1150', textScale: scale);
        final buttons = tester.getRect(find.byKey(TopActions.settingsKey));
        final change = tester.getRect(find.text('Change'));
        expect(buttons.bottom <= change.top, stacked, reason: stacked ? 'above Change' : 'beside Change');
        readsInFull(tester, 'Change');
        readsInFull(tester, 'STOP 1150');
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      });
    }
  });

  testWidgets('the Plan and Alerts pages have a back button, no gear, and no room kept for the tab bar',
      (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    await tester.tap(find.byKey(TopActions.planKey));
    await tester.pumpAndSettle();
    expect(find.byIcon(BBIcons.back), findsOneWidget);
    expect(find.byIcon(BBIcons.settings), findsNothing);
    final slivers = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).slivers;
    final end = (slivers.last as SliverToBoxAdapter).child! as SizedBox;
    expect(end.height, lessThan(BBNavBar.height), reason: 'no tab bar to clear');
    await tester.tap(find.byIcon(BBIcons.back));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(TopActions.alertsKey));
    await tester.pumpAndSettle();
    expect(find.byIcon(BBIcons.back), findsOneWidget);
    expect(find.byIcon(BBIcons.settings), findsNothing);
    final list =
        tester.widget<ListView>(find.descendant(of: find.byType(AlertsScreen), matching: find.byType(ListView)));
    expect((list.padding! as EdgeInsets).bottom, lessThan(BBNavBar.height), reason: 'no tab bar to clear');
  });

  testWidgets('the bell counts the active service alerts, as the Alerts tab did', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/',
        alerts: [_alert('Detour'), _alert('Closure'), _alert('Later', active: false)]);
    expect(find.descendant(of: find.byKey(TopActions.alertsKey), matching: find.text('2')), findsOneWidget);
    expect(find.bySemanticsLabel('Service alerts, 2 active'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('with no active alert the bell shows no count', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/', alerts: [_alert('Later', active: false)]);
    expect(find.descendant(of: find.byKey(TopActions.alertsKey), matching: find.byType(Text)), findsNothing);
    expect(tester.getSemantics(find.byKey(TopActions.alertsKey)), isSemantics(label: 'Service alerts', isButton: true));
    handle.dispose();
  });

  testWidgets('a quick double tap on a top button opens one page', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    await tester.tap(find.byKey(TopActions.planKey));
    await tester.tap(find.byKey(TopActions.planKey));
    await tester.pumpAndSettle();
    expect(find.byType(PlanScreen, skipOffstage: false), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(StopPickerScreen), findsOneWidget, reason: 'one back was enough');
  });

  testWidgets("an arrival alert's notification opens its Board, over whatever page was open", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/map');
    await tester.tap(find.byKey(TopActions.alertsKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertsScreen), findsOneWidget);
    expect(openNotificationRoute('/board/A', _router(tester).go), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(AlertsScreen), findsNothing);
    expect(find.byType(ArrivalBoardScreen), findsOneWidget);
    expect(_tab(tester), 0);
    await _unmount(tester);
  });

  for (final (link, page) in [('/plan', PlanScreen), ('/alerts', AlertsScreen)]) {
    testWidgets('a link straight to $link opens the page with the Board under it, so back stays in the app',
        (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: link);
      expect(find.byType(page), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(StopPickerScreen), findsOneWidget);
      expect(_tab(tester), 0);
    });
  }

  group('choosing a place on the map from the planner', () {
    testWidgets('round trip: the point fills in the plan, which sits over the plain map', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/', mapView: map.build);
      await tester.tap(find.byKey(TopActions.planKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick on map'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsNothing);
      expect(find.text('Tap the map to choose your destination'), findsOneWidget);
      expect(_tab(tester), 1);

      map.tap(47.5800, -52.7500); // Stop E
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsOneWidget);
      expect(_container(tester).read(planQueryProvider).to, StopPlace(stopId: 'E', name: 'Stop E'));
      expect(find.text('Stop E'), findsOneWidget);

      await tester.tap(find.byIcon(BBIcons.back));
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsNothing);
      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.text('Tap the map to choose your destination'), findsNothing, reason: 'the plain map');
      await _unmount(tester);
    });

    testWidgets('Cancel goes back to the plan with nothing set', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/', mapView: map.build);
      await tester.tap(find.byKey(TopActions.planKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a starting point'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick on map'));
      await tester.pumpAndSettle();
      expect(find.text('Tap the map to choose your starting point'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsOneWidget);
      expect(_container(tester).read(planQueryProvider).from, isNull);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Tap the map to choose your starting point'), findsNothing, reason: 'the plain map');
      await _unmount(tester);
    });

    testWidgets('the Map tab still opens the plain map: a pick left unfinished is over', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/map?pick=from', mapView: map.build);
      expect(find.text('Tap the map to choose your starting point'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(BBNavBar), matching: find.text('Board')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(BBNavBar), matching: find.text('Map')));
      await tester.pumpAndSettle();
      expect(find.text('Tap the map to choose your starting point'), findsNothing);
      await _unmount(tester);
    });
  });
}

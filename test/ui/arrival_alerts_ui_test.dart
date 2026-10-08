import 'dart:async';

import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:busboard_nl/ui/arrival_alerts/alert_bell.dart';
import 'package:busboard_nl/ui/arrival_alerts/alert_strip.dart';
import 'package:busboard_nl/ui/arrival_alerts/lead_time_sheet.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../kit/kit_test_helpers.dart';

class _Notes implements AlertNotifications {
  _Notes(this.grant);
  final bool grant;
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => grant;
  @override
  Future<bool> requestPermission() async => grant;
  @override
  Future<void> show(AlertMessage m) async {}
  @override
  Future<void> schedule(AlertMessage m, DateTime at) async {}
  @override
  Future<void> cancelScheduled() async {}
  @override
  Future<String?> launchRoute() async => null;
}

class _Runner implements AlertRunner {
  final started = <ArrivalAlert>[];
  bool throwOnStart = false;
  @override
  bool get watchesLive => true;
  @override
  Stream<void> get finished => const Stream.empty();
  @override
  Future<void> start(ArrivalAlert alert) async {
    if (throwOnStart) throw Exception('service failed to start');
    started.add(alert);
  }
  @override
  Future<void> update(ArrivalAlert alert) async {}
  @override
  Future<void> onBackground(ArrivalAlert alert) async {}
  @override
  Future<void> ensureRunning(ArrivalAlert alert) async {}
  @override
  Future<void> stop() async {}
}

ArrivalRow _row(int minutes, {String trip = 't1', String route = '10'}) => ArrivalRow(
      routeShortName: route,
      headsign: 'MUN-CNA-MI',
      scheduledTime: GtfsTime.fromSeconds(8 * 3600 + minutes * 60),
      predictedTime: GtfsTime.fromSeconds(8 * 3600 + minutes * 60),
      minutesAway: minutes,
      isLive: true,
      tripId: trip,
      vehicleNumber: '1415',
    );

Future<_Runner> _pump(WidgetTester tester, Widget child,
    {bool grant = true, double textScale = 1, double width = 390, bool failStart = false}) async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final runner = _Runner()..throwOnStart = failStart;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      alertRunnerProvider.overrideWithValue(runner),
      alertNotificationsProvider.overrideWithValue(_Notes(grant)),
    ],
    child: kitHost(child, textScale: textScale, width: width),
  ));
  await tester.pumpAndSettle();
  return runner;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('no bell under 5 or over 60 minutes', (tester) async {
    await _pump(tester, Column(children: [
      AlertBell(arrival: _row(2), stopId: '1150', stopName: 'MUN Centre'),
      AlertBell(arrival: _row(4), stopId: '1150', stopName: 'MUN Centre'),
      AlertBell(arrival: _row(61), stopId: '1150', stopName: 'MUN Centre'),
    ]));
    expect(find.byIcon(BBIcons.bell), findsNothing);
  });

  testWidgets('no bell at exactly 3 minutes: no lead time is possible', (tester) async {
    await _pump(tester, AlertBell(arrival: _row(3), stopId: '1150', stopName: 'MUN Centre'));
    expect(find.byIcon(BBIcons.bell), findsNothing);
  });

  testWidgets('bell → sheet → Set alert starts an alert with the chosen lead', (tester) async {
    final handle = tester.ensureSemantics();
    final runner = await _pump(tester, AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'));
    expect(find.bySemanticsLabel('Alert me before route 10 arrives'), findsOneWidget);
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    expect(find.text('Alert me when route 10 is'), findsOneWidget);
    expect(find.text('BusBoard will ask to send notifications, so it can alert you.'), findsNothing);
    await tester.tap(find.text('10 min'));
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(runner.started.single.leadMinutes, 10);
    expect(find.byIcon(BBIcons.bellFill), findsOneWidget);
    expect(find.bySemanticsLabel('Alert set for route 10. Cancel alert'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a bus 5 minutes away offers only 3 min', (tester) async {
    await _pump(tester, AlertBell(arrival: _row(5), stopId: '1150', stopName: 'MUN Centre'));
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    final ten = tester.widget<BBChip>(find.widgetWithText(BBChip, '10 min'));
    final five = tester.widget<BBChip>(find.widgetWithText(BBChip, '5 min'));
    final three = tester.widget<BBChip>(find.widgetWithText(BBChip, '3 min'));
    expect(ten.onTap, isNull);
    expect(five.onTap, isNull, reason: 'a 5 min lead on a 5 min bus would fire as it is set');
    expect(three.onTap, isNotNull);
  });

  testWidgets('permission denied: nothing starts, and Settings is offered', (tester) async {
    final runner = await _pump(tester, AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'), grant: false);
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    expect(find.text('BusBoard will ask to send notifications, so it can alert you.'), findsOneWidget);
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(runner.started, isEmpty);
    expect(find.text('Alerts need notifications'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('the alert failing to start says so, and nothing is set', (tester) async {
    await _pump(tester, AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'), failStart: true);
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't set the alert"), findsOneWidget);
    expect(find.text('Please try again.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't set the alert"), findsNothing);
    expect(find.byIcon(BBIcons.bellFill), findsNothing);
    expect(find.byIcon(BBIcons.bell), findsOneWidget);
  });

  testWidgets('the strip with an alert set does not overflow at 320 pt and 2× text', (tester) async {
    await _pump(tester, Column(children: [
      const AlertStrip(),
      AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'),
    ]), textScale: 2, width: 320);
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(find.text('Alert set · Route 10 · 5 min before'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second bell asks before replacing', (tester) async {
    final runner = await _pump(tester, Column(children: [
      AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'),
      AlertBell(arrival: _row(25, trip: 't2', route: '1'), stopId: '1150', stopName: 'MUN Centre'),
    ]));
    await tester.tap(find.byIcon(BBIcons.bell).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(BBIcons.bell).last);
    await tester.pumpAndSettle();
    expect(find.text('Replace your alert for route 10?'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(runner.started.map((a) => a.routeShortName), ['10', '1']);
  });

  testWidgets('the strip shows the alert and cancels it', (tester) async {
    await _pump(tester, Column(children: [
      const AlertStrip(),
      AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'),
    ]));
    expect(find.textContaining('Alert set'), findsNothing);
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(find.text('Alert set · Route 10 · 5 min before'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Alert set'), findsNothing);
  });

  testWidgets('a row with its bell does not overflow at 320 pt and 2× text', (tester) async {
    await _pump(
      tester,
      ArrivalRowTile(arrival: _row(20), action: AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre')),
      textScale: 2,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling after the bell has left the screen does not throw', (tester) async {
    final show = ValueNotifier(true);
    await _pump(tester, ValueListenableBuilder<bool>(
      valueListenable: show,
      builder: (_, on, _) =>
          on ? AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre') : const SizedBox(),
    ));
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(BBIcons.bellFill));
    await tester.pumpAndSettle();
    expect(find.text('Cancel your alert for route 10?'), findsOneWidget);
    show.value = false; // a Board refresh drops the row while the dialog is open
    await tester.pump();
    await tester.tap(find.text('Cancel alert'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tappable row with its bell exposes one row node, one bell node and no unlabeled button or tap target', (tester) async {
    final handle = tester.ensureSemantics();
    final arrival = _row(20);
    await _pump(
      tester,
      ArrivalRowTile(
        arrival: arrival,
        onTap: () {},
        action: AlertBell(arrival: arrival, stopId: '1150', stopName: 'MUN Centre'),
      ),
    );
    expect(find.bySemanticsLabel(ArrivalRowTile.semanticsLabel(arrival, use24h: true)), findsOneWidget);
    expect(find.bySemanticsLabel('Alert me before route 10 arrives'), findsOneWidget);

    final unlabeledButtons = <String>[];
    void walk(SemanticsNode n) {
      final d = n.getSemanticsData();
      if ((d.flagsCollection.isButton || d.hasAction(SemanticsAction.tap)) && d.label.isEmpty) {
        unlabeledButtons.add(d.toString());
      }
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }
    walk(tester.getSemantics(find.byType(ArrivalRowTile)));
    expect(unlabeledButtons, isEmpty);
    handle.dispose();
  });

  testWidgets('the sheet does not overflow at 320 pt and 2× text', (tester) async {
    await _pump(tester, Builder(builder: (context) => BBButton(
          label: 'open',
          onPressed: () => showLeadTimeSheet(context, arrival: _row(20), initialLead: 5, explainPermission: true),
        )), textScale: 2, width: 320);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

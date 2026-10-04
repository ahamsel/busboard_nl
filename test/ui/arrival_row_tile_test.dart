import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit/kit_test_helpers.dart';

ArrivalRow _row({
  int minutes = 4,
  bool isLive = false,
  bool isEnhanced = false,
  LiveStatus? status,
  String? vehicle,
  String? routeRun,
  String? near,
  GtfsTime? predicted,
}) =>
    ArrivalRow(
      routeShortName: '29',
      headsign: 'Signal Hill Rd',
      scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: predicted,
      minutesAway: minutes,
      liveStatus: status,
      isLive: isLive,
      tripId: 't',
      vehicleNumber: vehicle,
      isEnhanced: isEnhanced,
      routeRun: routeRun,
      currentLocation: near,
    );

void main() {
  test('status matrix in plain words', () {
    expect(ArrivalRowTile.statusOf(_row(isEnhanced: true, isLive: true)), ('Live', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isEnhanced: true)), ('Scheduled', BBPillTone.neutral));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.ahead)), ('Early', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.behind)), ('Late', BBPillTone.warn));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.onTime)), ('On time', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isLive: true)), ('Live', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row()), ('Scheduled', BBPillTone.neutral));
  });

  test('screen-reader sentence', () {
    expect(ArrivalRowTile.semanticsLabel(_row(isEnhanced: true, isLive: true, minutes: 4)),
        'Route 29 Signal Hill Rd, live, 4 minutes');
    expect(ArrivalRowTile.semanticsLabel(_row(minutes: 1)), 'Route 29 Signal Hill Rd, scheduled, 1 minute');
    expect(ArrivalRowTile.semanticsLabel(_row(minutes: 0)), 'Route 29 Signal Hill Rd, scheduled, now');
  });

  test('screen-reader sentence includes the expected time for live rows', () {
    expect(
      ArrivalRowTile.semanticsLabel(_row(isLive: true, status: LiveStatus.behind, minutes: 15, predicted: GtfsTime.parse('09:55:00'))),
      'Route 29 Signal Hill Rd, late, 15 minutes, expected 09:55',
    );
    // Scheduled rows (no prediction) and live rows without a predicted time stay as before.
    expect(ArrivalRowTile.semanticsLabel(_row(isLive: true, minutes: 4)), 'Route 29 Signal Hill Rd, live, 4 minutes');
    expect(ArrivalRowTile.semanticsLabel(_row(predicted: GtfsTime.parse('09:55:00'))), 'Route 29 Signal Hill Rd, scheduled, 4 minutes');
  });

  testWidgets('live row shows run/bus, near, exp and struck-through sched', (tester) async {
    await tester.pumpWidget(kitHost(ArrivalRowTile(
      arrival: _row(isLive: true, status: LiveStatus.behind, vehicle: '2134', routeRun: '29-1', near: 'MUN Centre',
          predicted: GtfsTime.parse('09:55:00')),
    )));
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('29-1 · Bus 2134'), findsOneWidget);
    expect(find.text('Near MUN Centre'), findsOneWidget);
    expect(find.text('exp 09:55'), findsOneWidget);
    final sched = tester.widget<Text>(find.text('sched 09:52'));
    expect(sched.style!.decoration, TextDecoration.lineThrough);
  });

  testWidgets('schedule-only row shows just the scheduled time', (tester) async {
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(vehicle: '2134', near: 'X'))));
    expect(find.text('09:52'), findsOneWidget);
    expect(find.textContaining('Bus'), findsNothing);
    expect(find.textContaining('Near'), findsNothing);
    expect(find.textContaining('exp'), findsNothing);
  });

  testWidgets('minutes: soon colour at <=5, ink above; Now with no unit', (tester) async {
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(minutes: 5))));
    expect(tester.widget<Text>(find.text('5')).style!.color, BBColors.light.soon);
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(minutes: 6))));
    expect(tester.widget<Text>(find.text('6')).style!.color, BBColors.light.ink);
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(minutes: 0))));
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('min'), findsNothing);
  });

  testWidgets('route badge uses the route colour and the row is one semantics node', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(isEnhanced: true, isLive: true))));
    expect(find.byType(RouteBadge), findsOneWidget);
    expect(find.bySemanticsLabel('Route 29 Signal Hill Rd, live, 4 minutes'), findsOneWidget);
    expect(find.bySemanticsLabel('Signal Hill Rd'), findsNothing);
    handle.dispose();
  });

  testWidgets('semantics node announces the expected time of a live row', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(ArrivalRowTile(
      arrival: _row(isLive: true, status: LiveStatus.behind, predicted: GtfsTime.parse('09:55:00')),
    )));
    expect(find.bySemanticsLabel('Route 29 Signal Hill Rd, late, 4 minutes, expected 09:55'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('no overflow at text scale 2.0 on 320pt', (tester) async {
    await tester.pumpWidget(kitHost(
      ArrivalRowTile(arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134', routeRun: '29-1',
          near: 'Elizabeth Ave at Allandale Rd', predicted: GtfsTime.parse('09:55:00'), minutes: 15)),
      textScale: 2.0,
      width: 320,
    ));
    expect(tester.takeException(), isNull);
  });
}

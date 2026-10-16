import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
  String headsign = 'Signal Hill Rd',
}) =>
    ArrivalRow(
      routeShortName: '29',
      headsign: headsign,
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
  // The real fonts, so a row lays out as it does on a phone (heights are compared below).
  setUpAll(loadAppFonts);

  test('status matrix in plain words', () {
    expect(ArrivalRowTile.statusOf(_row(isEnhanced: true, isLive: true)), ('Live', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isEnhanced: true)), ('Scheduled', BBPillTone.neutral));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.ahead)), ('Early', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.behind)), ('Late', BBPillTone.warn));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.onTime)), ('On time', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isLive: true)), ('Live', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row()), ('Scheduled', BBPillTone.neutral));
  });

  testWidgets("the feed's all-caps trip name reads in title case, on screen and to a screen reader", (tester) async {
    final handle = tester.ensureSemantics();
    final row = _row(headsign: 'AVALON MALL - MUN CENTRE - DOWNTOWN');
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: row, onExplain: () {})));
    expect(find.text('Avalon Mall - MUN Centre - Downtown'), findsOneWidget);
    expect(find.text('AVALON MALL - MUN CENTRE - DOWNTOWN'), findsNothing);
    expect(ArrivalRowTile.semanticsLabel(row, use24h: true),
        'Route 29 Avalon Mall - MUN Centre - Downtown, scheduled, 4 minutes');
    expect(find.semantics.byLabel('Route 29 Avalon Mall - MUN Centre - Downtown, scheduled, 4 minutes'), findsOne);
    handle.dispose();
  });

  test('screen-reader sentence', () {
    expect(ArrivalRowTile.semanticsLabel(_row(isEnhanced: true, isLive: true, minutes: 4), use24h: true),
        'Route 29 Signal Hill Rd, live, 4 minutes');
    expect(ArrivalRowTile.semanticsLabel(_row(minutes: 1), use24h: true), 'Route 29 Signal Hill Rd, scheduled, 1 minute');
    expect(ArrivalRowTile.semanticsLabel(_row(minutes: 0), use24h: true), 'Route 29 Signal Hill Rd, scheduled, now');
  });

  test('screen-reader sentence includes the expected time for live rows', () {
    expect(
      ArrivalRowTile.semanticsLabel(_row(isLive: true, status: LiveStatus.behind, minutes: 15, predicted: GtfsTime.parse('09:55:00')), use24h: true),
      'Route 29 Signal Hill Rd, late, 15 minutes, expected 09:55',
    );
    expect(
      ArrivalRowTile.semanticsLabel(_row(isLive: true, status: LiveStatus.behind, minutes: 15, predicted: GtfsTime.parse('09:55:00')), use24h: false),
      'Route 29 Signal Hill Rd, late, 15 minutes, expected 9:55 AM',
    );
    // Scheduled rows (no prediction) and live rows without a predicted time stay as before.
    expect(ArrivalRowTile.semanticsLabel(_row(isLive: true, minutes: 4), use24h: true), 'Route 29 Signal Hill Rd, live, 4 minutes');
    expect(ArrivalRowTile.semanticsLabel(_row(predicted: GtfsTime.parse('09:55:00')), use24h: true), 'Route 29 Signal Hill Rd, scheduled, 4 minutes');
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

  testWidgets('the scheduled time is struck through with one line, not the app fallback\'s double line',
      (tester) async {
    // In the app no Material sits above the rows, so the inherited text style is Flutter's debug fallback, whose
    // decoration is a double line: a strike-through that kept that style drew a second line under the text.
    await tester.pumpWidget(MaterialApp(
      theme: BBTheme.light(),
      home: Center(
        child: ArrivalRowTile(
          arrival: _row(isLive: true, status: LiveStatus.behind, predicted: GtfsTime.parse('09:55:00')),
        ),
      ),
    ));
    final sched = tester.renderObject<RenderParagraph>(find.textContaining('sched'));
    expect(sched.text.style?.decoration, TextDecoration.lineThrough);
    expect(sched.text.style?.decorationStyle, TextDecorationStyle.solid);
  });

  testWidgets("times follow the device's 12-hour setting", (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(
      ArrivalRowTile(arrival: _row(isLive: true, status: LiveStatus.behind, predicted: GtfsTime.parse('09:55:00'))),
      use24h: false,
    ));
    expect(find.text('exp 9:55 AM'), findsOneWidget);
    expect(find.text('sched 9:52 AM'), findsOneWidget);
    expect(find.bySemanticsLabel('Route 29 Signal Hill Rd, late, 4 minutes, expected 9:55 AM'), findsOneWidget);
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row()), use24h: false));
    expect(find.text('9:52 AM'), findsOneWidget);
    handle.dispose();
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

  testWidgets('a live row with onTap calls it and offers a follow action to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(kitHost(ArrivalRowTile(
      arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2573'),
      onTap: () => taps++,
    )));
    expect(
      find.semantics.byLabel('Route 29 Signal Hill Rd, on time, 4 minutes'),
      isSemantics(
        label: 'Route 29 Signal Hill Rd, on time, 4 minutes',
        isButton: true,
        hasTapAction: true,
        onTapHint: 'follow bus 2573 on the map',
      ),
    );
    await tester.tap(find.text('Signal Hill Rd'));
    expect(taps, 1);
    handle.dispose();
  });

  group('the Follow pill', () {
    testWidgets('a followable live row shows "Follow 2134" in place of "Bus 2134", in brandSoft and brandInk',
        (tester) async {
      await tester.pumpWidget(kitHost(ArrivalRowTile(
        arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134', routeRun: '29-1'),
        onTap: () {},
      )));
      expect(find.textContaining('Follow 2134'), findsOneWidget);
      expect(find.text('29-1'), findsOneWidget);
      expect(find.textContaining('Bus 2134'), findsNothing);
      final box = tester.widget<DecoratedBox>(find.byKey(ArrivalRowTile.followKey));
      expect((box.decoration as BoxDecoration).color, BBColors.light.brandSoft);
      final text = tester.widget<Text>(find.textContaining('Follow 2134'));
      expect(text.style!.color, BBColors.light.brandInk);
    });

    testWidgets('the row says the follow for it: its sentence, then "Follow bus 2134 on the map"', (tester) async {
      final handle = tester.ensureSemantics();
      Future<void> pump() => tester.pumpWidget(kitHost(ArrivalRowTile(
            arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134'),
            onTap: () {},
          )));
      // TalkBack says the tap hint ("double tap to follow bus 2134 on the map"), as in 1.4.1.
      await pump();
      expect(
        find.semantics.byLabel('Route 29 Signal Hill Rd, on time, 4 minutes'),
        isSemantics(
          label: 'Route 29 Signal Hill Rd, on time, 4 minutes',
          isButton: true,
          hasTapAction: true,
          onTapHint: 'follow bus 2134 on the map',
        ),
      );
      // VoiceOver doesn't speak tap hints, so on iPhone the follow is the row's hint.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pump();
      expect(
        find.semantics.byLabel('Route 29 Signal Hill Rd, on time, 4 minutes'),
        isSemantics(
          label: 'Route 29 Signal Hill Rd, on time, 4 minutes',
          hint: 'Follow bus 2134 on the map',
          isButton: true,
          hasTapAction: true,
        ),
      );
      debugDefaultTargetPlatformOverride = null;
      handle.dispose();
    });

    testWidgets('it is a cue inside the row: no target or node of its own, and a tap on it follows as the row does',
        (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(kitHost(ArrivalRowTile(
        arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134'),
        onTap: () => taps++,
      )));
      final pill = find.byKey(ArrivalRowTile.followKey);
      expect(find.descendant(of: find.byType(ArrivalRowTile), matching: find.byType(BBPressable)), findsOneWidget,
          reason: "the row's card is the only target");
      expect(find.ancestor(of: pill, matching: find.byType(BBPressable)), findsOneWidget);
      expect(find.semantics.byLabel('Follow bus 2134 on the map'), findsNothing, reason: 'no node of its own');
      await tester.tap(pill);
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('it adds no height: a followable row is as tall as the same row in 1.4.1 ("29-1 · Bus 2134")',
        (tester) async {
      for (final near in [null, 'MUN Centre']) {
        final row = _row(isLive: true, status: LiveStatus.ahead, vehicle: '2134', routeRun: '29-1', near: near,
            predicted: GtfsTime.parse('09:51:00'));
        // A row with no follow is laid out exactly as 1.4.1's row was: the status pill, then "29-1 · Bus 2134".
        await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: row)));
        expect(find.text('29-1 · Bus 2134'), findsOneWidget);
        final plain = tester.getSize(find.byType(ArrivalRowTile)).height;
        await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: row, onTap: () {})));
        expect(find.byKey(ArrivalRowTile.followKey), findsOneWidget);
        expect(tester.getSize(find.byType(ArrivalRowTile)).height, plain, reason: 'near: $near');
        final status = tester.getRect(find.text('Early'));
        final pill = tester.getRect(find.byKey(ArrivalRowTile.followKey));
        expect(pill.height, lessThanOrEqualTo(tester.getSize(find.byType(BBPill)).height),
            reason: 'the pill is no taller than the status pill beside it');
        expect(pill.center.dy, closeTo(status.center.dy, 0.5), reason: 'it sits on the status line');
      }
    });

    testWidgets('no pill without a follow, or on a scheduled row', (tester) async {
      await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(isLive: true, vehicle: '2134', routeRun: '29-1'))));
      expect(find.byKey(ArrivalRowTile.followKey), findsNothing);
      expect(find.text('29-1 · Bus 2134'), findsOneWidget, reason: 'a row that cannot be followed keeps the plain number');
      await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(), onExplain: () {})));
      expect(find.byKey(ArrivalRowTile.followKey), findsNothing);
    });

    testWidgets('at 2x text on 320 pt the pill reads in full', (tester) async {
      await tester.pumpWidget(kitHost(
        ArrivalRowTile(
          arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134', routeRun: '29-1', minutes: 15),
          onTap: () {},
        ),
        textScale: 2.0,
        width: 320,
      ));
      expect(tester.takeException(), isNull);
      // The pill's text has no line limit (it wraps), so `didExceedMaxLines` is always false: check where it sits.
      final pill = tester.getRect(find.byKey(ArrivalRowTile.followKey));
      final text = tester.getRect(find.textContaining('Follow 2134'));
      final row = tester.getRect(find.byType(ArrivalRowTile));
      expect(row.width, 320);
      expect(pill.left, greaterThanOrEqualTo(row.left));
      expect(pill.right, lessThanOrEqualTo(row.right), reason: 'the pill stays inside the 320 pt row');
      expect(text.left, greaterThanOrEqualTo(pill.left));
      expect(text.right, lessThanOrEqualTo(pill.right), reason: 'all the words are inside the pill');
      expect(text.top, greaterThanOrEqualTo(pill.top));
      expect(text.bottom, lessThanOrEqualTo(pill.bottom), reason: 'a wrapped second line grows the pill');
    });
  });

  group('a row with no bus to follow', () {
    test('says why: a scheduled row has no bus yet, a live row has no number yet', () {
      expect(ArrivalRowTile.whyNotFollowable(_row()), "No bus on this trip yet. You can follow it once it's live.");
      expect(ArrivalRowTile.whyNotFollowable(_row(isLive: true)),
          "This bus isn't sharing its number yet, so it can't be followed.");
    });

    testWidgets('onExplain makes it a button that explains, with no follow hint', (tester) async {
      final handle = tester.ensureSemantics();
      var explained = 0;
      await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(), onExplain: () => explained++)));
      expect(
        find.semantics.byLabel('Route 29 Signal Hill Rd, scheduled, 4 minutes'),
        isSemantics(label: 'Route 29 Signal Hill Rd, scheduled, 4 minutes', isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text('Signal Hill Rd'));
      expect(explained, 1);
      handle.dispose();
    });
  });

  testWidgets('a row without onTap has no tap action', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(isLive: true, vehicle: '2573'))));
    expect(
      find.semantics.byLabel('Route 29 Signal Hill Rd, live, 4 minutes'),
      isSemantics(label: 'Route 29 Signal Hill Rd, live, 4 minutes', isButton: false, hasTapAction: false),
    );
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

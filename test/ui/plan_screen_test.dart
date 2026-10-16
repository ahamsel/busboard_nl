import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/trip_planner/journey_card.dart';
import 'package:busboard_nl/ui/trip_planner/place_picker_sheet.dart';
import 'package:busboard_nl/ui/trip_planner/plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

final _now = DateTime(testDay.year, testDay.month, testDay.day, 8, 1);

/// Opens the picker from the row showing [placeholder], types [query] and taps [row].
Future<void> _choose(WidgetTester tester, String placeholder, String query, String row) async {
  await tester.tap(find.text(placeholder));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(EditableText), query);
  await tester.pumpAndSettle();
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
}

Future<void> _chooseAtoC(WidgetTester tester) async {
  await _choose(tester, 'Choose a starting point', 'A', 'Stop A (A)');
  await _choose(tester, 'Choose a destination', 'C', 'Stop C (C)');
}

String _textIn(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .join(' ');

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(PlanScreen)));

void main() {
  // Real glyph widths, so the 2x text checks measure what a phone shows.
  setUpAll(loadAppFonts);

  testWidgets('the nav bar has Board, Map, Alerts and Plan; Plan opens the planner', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
    final bar = find.byType(BBNavBar);
    for (final label in ['Board', 'Map', 'Alerts', 'Plan']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
    }
    expect(tester.widget<BBNavBar>(bar).items, hasLength(4));
    await tester.tap(find.descendant(of: bar, matching: find.text('Plan')));
    await tester.pumpAndSettle();
    expect(find.text('Plan a trip'), findsOneWidget);
  });

  testWidgets('choosing A then C shows the 8:10 → 8:20 journey', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    expect(find.text("Choose where you're going"), findsOneWidget);
    await _chooseAtoC(tester);
    expect(find.byType(JourneyCard), findsWidgets);
    expect(
      find.descendant(of: find.byType(JourneyCard).first, matching: find.textContaining(RegExp(r'^8:10\b.*→ 8:20\b'))),
      findsOneWidget,
    );
  });

  testWidgets('the empty results name whichever end is missing: the destination first, else the start',
      (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    expect(find.text("Choose where you're going"), findsOneWidget, reason: 'nothing chosen yet');
    await _choose(tester, 'Choose a destination', 'C', 'Stop C (C)');
    expect(find.text("Choose where you're starting"), findsOneWidget, reason: 'only the start is missing');
    expect(find.text("Choose where you're going"), findsNothing);
    _container(tester).read(planQueryProvider.notifier)
      ..setTo(null)
      ..setFrom(StopPlace(stopId: 'A', name: 'Stop A'));
    await tester.pumpAndSettle();
    expect(find.text("Choose where you're going"), findsOneWidget, reason: 'only the destination is missing');
  });

  testWidgets("the place picker's search field keeps its name for screen readers once text is typed", (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await tester.tap(find.text('Choose a destination'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'C');
    await tester.pumpAndSettle();
    final field = tester.getSemantics(find.byType(EditableText));
    expect(field.label, 'Stop number or name', reason: 'a stable name, read with the typed value');
    expect(field.value, 'C');
    handle.dispose();
  });

  testWidgets('the 30 s live refresh keeps the results up instead of flashing the loading dots', (tester) async {
    // A feed that takes 2 s to answer, as a phone network can.
    final slow = MockClient((_) => Future.delayed(const Duration(seconds: 2), () => http.Response('', 503)));
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, liveClient: slow);
    await _chooseAtoC(tester);
    expect(find.byType(JourneyCard), findsWidgets);
    // Past two refreshes, a second at a time.
    for (var i = 0; i < 65; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BBLoading), findsNothing, reason: 'at ${i + 1} s');
      expect(find.byType(JourneyCard), findsWidgets);
    }
  });

  testWidgets('swap exchanges the start and the destination', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _chooseAtoC(tester);
    await tester.tap(find.bySemanticsLabel('Swap start and destination'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, PlanScreen.fromRowKey), contains('Stop C'));
    expect(_textIn(tester, PlanScreen.toRowKey), contains('Stop A'));
  });

  testWidgets('Arrive by 8:25 shows only journeys that get there by 8:25', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _chooseAtoC(tester);
    expect(find.byKey(PlanScreen.timeButtonKey), findsNothing);
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    expect(find.byKey(PlanScreen.timeButtonKey), findsOneWidget);

    await tester.tap(find.byKey(PlanScreen.timeButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '8');
    await tester.enterText(fields.at(1), '25');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(_textIn(tester, PlanScreen.timeButtonKey), contains('8:25'));
    final cards = tester.widgetList<JourneyCard>(find.byType(JourneyCard)).toList();
    expect(cards, isNotEmpty);
    final by = DateTime(testDay.year, testDay.month, testDay.day, 8, 25);
    for (final c in cards) {
      expect(c.journey.at(c.journey.arrives).isAfter(by), isFalse);
    }
  });

  testWidgets('switching to Arrive by starts at 8:35, not now, so the first view has buses', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _chooseAtoC(tester);
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, PlanScreen.timeButtonKey), contains('8:35'));
    expect(find.text('No buses get you there at that time'), findsNothing);
    expect(find.byType(JourneyCard), findsWidgets);
  });

  testWidgets('a destination no bus reaches says so', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _choose(tester, 'Choose a starting point', 'A', 'Stop A (A)');
    await _choose(tester, 'Choose a destination', 'H', 'Stop H (H)');
    expect(find.text('No buses get you there at that time'), findsOneWidget);
    expect(find.byType(JourneyCard), findsNothing);
  });

  testWidgets('late at night, it names tomorrow\'s first bus', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: DateTime(testDay.year, testDay.month, testDay.day, 23));
    await _chooseAtoC(tester);
    expect(find.text('No buses get you there at that time'), findsOneWidget);
    expect(find.text('The next bus that gets you there leaves tomorrow at 8:00 AM'), findsOneWidget);
  });

  testWidgets("leave by late on a later day names the day the next bus runs, not tomorrow", (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, textScale: 2);
    _container(tester).read(planQueryProvider.notifier)
      ..setFrom(StopPlace(stopId: 'A', name: 'Stop A'))
      ..setTo(StopPlace(stopId: 'C', name: 'Stop C'))
      ..setMode(PlanMode.leaveBy)
      ..setTime(DateTime(testDay.year, testDay.month, testDay.day + 2, 22));
    await tester.pumpAndSettle();
    const message = 'The next bus that gets you there leaves on Sat, Oct 10 at 8:00 AM';
    final list = find.descendant(of: find.byType(PlanScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text(message), 200, scrollable: list);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(find.text(message)).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a start far from every stop asks for a closer point', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    final q = _container(tester).read(planQueryProvider.notifier);
    q.setFrom(PinPlace(lat: 47.0, lon: -52.0, label: 'Pin'));
    q.setTo(StopPlace(stopId: 'C', name: 'Stop C'));
    await tester.pumpAndSettle();
    expect(find.text('Too far from a bus stop'), findsOneWidget);
    expect(find.text('Pick a closer point for your start.'), findsOneWidget);
  });

  testWidgets('a planning failure says so', (tester) async {
    await pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: _now,
      overrides: [planResultsProvider.overrideWith((ref) async => throw StateError('broken index'))],
    );
    expect(find.text("Couldn't plan that trip"), findsOneWidget);
    expect(find.text('Try again in a moment.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the date button reads Today, then Tomorrow once tomorrow is picked', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await tester.tap(find.text('Leave by'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, PlanScreen.dateButtonKey), contains('Today'));
    await tester.tap(find.byKey(PlanScreen.dateButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${testDay.day + 1}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, PlanScreen.dateButtonKey), contains('Tomorrow'));
    final time = _container(tester).read(planQueryProvider).time!;
    // Leave by starts at 8:35 (8:01 + 30 min, rounded up); the date picker keeps that time of day.
    expect((time.day, time.hour, time.minute), (testDay.day + 1, 8, 35));
  });

  testWidgets('an Arrive by time never picked moves on with the clock, and the plan with it', (tester) async {
    var clock = _now;
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, clock: () => clock);
    await _chooseAtoC(tester);
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, PlanScreen.timeButtonKey), contains('8:35')); // 8:01 + 30 min, rounded up
    bool arrivesAt840(PlanOutcome? o) => o is PlanFound && o.journeys.any((j) => j.arrives == 8 * 3600 + 40 * 60);
    expect(arrivesAt840(_container(tester).read(planResultsProvider).value), isFalse);

    clock = _now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(_textIn(tester, PlanScreen.timeButtonKey), contains('8:40'));
    expect(_container(tester).read(planQueryProvider).time, isNull, reason: 'still not picked');
    expect(arrivesAt840(_container(tester).read(planResultsProvider).value), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('My location reads "Location is off" and does nothing when location is off', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await tester.tap(find.text('Choose a starting point'));
    await tester.pumpAndSettle();
    expect(find.text('Location is off'), findsOneWidget);
    await tester.tap(find.text('Location is off'));
    await tester.pumpAndSettle();
    expect(find.text('Location is off'), findsOneWidget);
  });

  testWidgets('My location fills the start with the phone\'s position', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, geolocator: FixedGeolocator(47.5601, -52.7501));
    await tester.tap(find.text('Choose a starting point'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My location'));
    await tester.pumpAndSettle();
    final from = _container(tester).read(planQueryProvider).from;
    expect(from, isA<PinPlace>().having((p) => p.label, 'label', 'My location'));
    expect(_textIn(tester, PlanScreen.fromRowKey), contains('My location'));
  });

  testWidgets('My location says it is finding you, and gives up after 10 s so it can be tried again', (tester) async {
    final handle = tester.ensureSemantics();
    final geo = NoFixGeolocator();
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, geolocator: geo);
    await tester.tap(find.text('Choose a starting point'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My location'));
    await tester.pump();
    expect(find.text('Finding you…'), findsOneWidget);
    expect(find.bySemanticsLabel('Finding you…'), findsOneWidget);
    expect(geo.requests.single?.timeLimit, const Duration(seconds: 10));

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text("Couldn't find your location"), findsOneWidget);
    expect(find.bySemanticsLabel("Couldn't find your location"), findsOneWidget);
    expect(_container(tester).read(planQueryProvider).from, isNull);

    await tester.tap(find.text("Couldn't find your location"));
    await tester.pump();
    expect(find.text('Finding you…'), findsOneWidget, reason: 'the row works again');
    expect(geo.requests, hasLength(2));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    handle.dispose();
  });

  testWidgets('at 2x text the finding-you and gave-up rows read in full', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, geolocator: NoFixGeolocator(), textScale: 2);
    await tester.tap(find.text('Choose a starting point'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My location'));
    await tester.pump();
    expect(tester.renderObject<RenderParagraph>(find.text('Finding you…')).didExceedMaxLines, isFalse);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(tester.renderObject<RenderParagraph>(find.text("Couldn't find your location")).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('matching takes stop ids that start with the text or names that contain it, 20 at most, by id', () {
    final net = TestNetwork();
    for (var i = 0; i < 30; i++) {
      net.repo.stopsById['${100 + i}'] = StopInfo(
        stopId: '${100 + i}',
        stopName: 'Elm St',
        stopLat: 47.56,
        stopLon: -52.75,
      );
    }
    expect(matchStops(net.repo, '1').map((s) => s.stopId), [for (var i = 0; i < 20; i++) '${100 + i}']);
    expect(matchStops(net.repo, 'stop c').map((s) => s.stopId), ['C']);
    expect(matchStops(net.repo, 'ELM').length, 20);
    expect(matchStops(net.repo, '  '), isEmpty);
  });

  testWidgets('the picker lists the matching stops as "Name (id)"', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await tester.tap(find.text('Choose a starting point'));
    await tester.pumpAndSettle();
    expect(find.text('Stop number or name'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'stop');
    await tester.pumpAndSettle();
    expect(find.text('Stop A (A)'), findsOneWidget);
    expect(find.text('Stop B (B)'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Stop A (A)')).dy, lessThan(tester.getTopLeft(find.text('Stop B (B)')).dy));
  });

  testWidgets('Pick on map sends the rider to the map to drop the pin', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await tester.tap(find.text('Choose a destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick on map'));
    await tester.pump();
    final router = GoRouter.of(tester.element(find.byType(BBNavBar)));
    expect(router.state.uri.toString(), '/map?pick=to');
    // The real map tab started its own refresh timers; let them run out after it goes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('nothing overflows at 2x text, empty or with results', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Arrive by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(PlanScreen.dateButtonKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Leave now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave now'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose a starting point'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a starting point'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(EditableText), 'A');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop A (A)'));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(PlanScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Choose a destination'), 100, scrollable: list);
    await _choose(tester, 'Choose a destination', 'C', 'Stop C (C)');
    await tester.scrollUntilVisible(find.byType(JourneyCard).last, 200, scrollable: list);
    await tester.pumpAndSettle();
    expect(find.byType(JourneyCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(320, 568), Size(390, 844)]) {
    testWidgets('at 2x text on ${size.width.toInt()}x${size.height.toInt()} every When label reads in full', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, textScale: 2);
      for (final label in ['Leave now', 'Leave by', 'Arrive by']) {
        expect(find.text(label), findsOneWidget);
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        final p = tester.renderObject<RenderParagraph>(find.text(label));
        expect(p.didExceedMaxLines, isFalse, reason: '"$label" is cut short');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('every control has a screen-reader label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    expect(find.bySemanticsLabel('From: not chosen'), findsOneWidget);
    expect(find.bySemanticsLabel('To: not chosen'), findsOneWidget);
    expect(find.bySemanticsLabel('Swap start and destination'), findsOneWidget);
    for (final s in ['Leave now', 'Leave by', 'Arrive by']) {
      expect(find.bySemanticsLabel(s), findsOneWidget);
    }
    await _chooseAtoC(tester);
    expect(find.bySemanticsLabel('From: Stop A'), findsOneWidget);
    expect(find.bySemanticsLabel('To: Stop C'), findsOneWidget);
    expect(tester.getSemantics(find.byType(JourneyCard).first).label, contains('Leave 8:10'));
    await tester.tap(find.text('Leave by'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Time, ')), findsOneWidget);
    expect(find.bySemanticsLabel('Date, Today'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping a journey opens its detail', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _chooseAtoC(tester);
    await tester.tap(find.byType(JourneyCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Your trip'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is RouteBadge && w.label == '1'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^8:10\b.*→ 8:20\b')), findsOneWidget);
  });
}

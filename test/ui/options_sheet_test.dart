import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/journey_on_map_provider.dart';
import 'package:busboard_nl/state/map_pick_provider.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/options_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/search/search_screen.dart';
import 'package:busboard_nl/ui/trip_planner/journey_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

final _now = DateTime(testDay.year, testDay.month, testDay.day, 8, 1);

final _a = StopPlace(stopId: 'A', name: 'Stop A');
final _c = StopPlace(stopId: 'C', name: 'Stop C');

String _textIn(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .join(' ');

/// Home's providers, also while the search is pushed over it.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen, skipOffstage: false)));

/// The same bus trip: a live refresh plans it again as a new [Journey].
Matcher _sameTripAs(Journey j) => isA<Journey>()
    .having((x) => x.departs, 'departs', j.departs)
    .having((x) => x.legs.whereType<RideLeg>().map((r) => r.tripId).toList(), 'rides',
        j.legs.whereType<RideLeg>().map((r) => r.tripId).toList());

/// The sheet's own scrolling list.
Finder get _sheetList => find.descendant(of: find.byKey(BBSheet.cardKey), matching: find.byType(Scrollable)).first;

/// Pulls the sheet up to its full height.
Future<void> _pullUp(WidgetTester tester) async {
  await tester.drag(find.bySemanticsLabel('Map sheet'), const Offset(0, -600));
  await tester.pumpAndSettle();
}

/// Sets the draft to [from] → [to] (when given) and opens the trip options, pulled up to full height.
Future<void> _openOptions(WidgetTester tester, {Place? from, Place? to}) async {
  final c = _container(tester);
  if (from != null && to != null) c.read(planQueryProvider.notifier).setTrip(from, to);
  c.read(homeSheetProvider.notifier).open(const OptionsSheet());
  await tester.pumpAndSettle();
  await _pullUp(tester);
}

/// Home, then the options for Stop A → Stop C.
Future<void> _openAtoC(WidgetTester tester) async {
  await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
  await _openOptions(tester, from: _a, to: _c);
}

/// Taps the From row, which opens the search for the start.
Future<void> _openFromSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(OptionsSheetContent.fromRowKey));
  await tester.pumpAndSettle();
  expect(tester.widget<SearchScreen>(find.byType(SearchScreen)).end, MapPick.from);
}

void main() {
  // Real glyph widths, so the 2x text checks measure what a phone shows.
  setUpAll(loadAppFonts);

  testWidgets('options for A → C show the 8:10 → 8:20 journey', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _openOptions(tester);
    expect(find.text("Choose where you're going"), findsOneWidget);
    _container(tester).read(planQueryProvider.notifier).setTrip(_a, _c);
    await tester.pumpAndSettle();
    expect(find.text('To Stop C'), findsOneWidget);
    expect(find.byType(JourneyCard), findsWidgets);
    expect(
      find.descendant(of: find.byType(JourneyCard).first, matching: find.textContaining(RegExp(r'^8:10\b.*→ 8:20\b'))),
      findsOneWidget,
    );
  });

  testWidgets('the first journey is drawn on the map as soon as the results arrive', (tester) async {
    await _openAtoC(tester);
    final c = _container(tester);
    final results = c.read(planResultsProvider).value;
    expect(results, isA<PlanFound>());
    expect(c.read(journeyOnMapProvider), _sameTripAs((results! as PlanFound).journeys.first));
    expect(find.bySemanticsLabel('Hide the trip from the map'), findsOneWidget);
  });

  testWidgets('the 30 s live refresh keeps the results up instead of flashing the loading dots', (tester) async {
    // A feed that takes 2 s to answer, as a phone network can.
    final slow = MockClient((_) => Future.delayed(const Duration(seconds: 2), () => http.Response('', 503)));
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, liveClient: slow);
    await _openOptions(tester, from: _a, to: _c);
    expect(find.byType(JourneyCard), findsWidgets);
    // Past two refreshes, a second at a time.
    for (var i = 0; i < 65; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BBLoading), findsNothing, reason: 'at ${i + 1} s');
      expect(find.byType(JourneyCard), findsWidgets);
    }
  });

  testWidgets('swap exchanges the start and the destination', (tester) async {
    await _openAtoC(tester);
    await tester.tap(find.bySemanticsLabel('Swap start and destination'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, OptionsSheetContent.fromRowKey), contains('Stop C'));
    expect(_textIn(tester, OptionsSheetContent.toRowKey), contains('Stop A'));
  });

  testWidgets('Arrive by 8:25 shows only journeys that get there by 8:25', (tester) async {
    await _openAtoC(tester);
    expect(find.byKey(OptionsSheetContent.timeButtonKey), findsNothing);
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    expect(find.byKey(OptionsSheetContent.timeButtonKey), findsOneWidget);

    await tester.tap(find.byKey(OptionsSheetContent.timeButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '8');
    await tester.enterText(fields.at(1), '25');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(_textIn(tester, OptionsSheetContent.timeButtonKey), contains('8:25'));
    final cards = tester.widgetList<JourneyCard>(find.byType(JourneyCard)).toList();
    expect(cards, isNotEmpty);
    final by = DateTime(testDay.year, testDay.month, testDay.day, 8, 25);
    for (final c in cards) {
      expect(c.journey.at(c.journey.arrives).isAfter(by), isFalse);
    }
  });

  testWidgets('switching to Arrive by starts at 8:35, not now, so the first view has buses', (tester) async {
    await _openAtoC(tester);
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, OptionsSheetContent.timeButtonKey), contains('8:35'));
    expect(find.text('No buses get you there at that time'), findsNothing);
    expect(find.byType(JourneyCard), findsWidgets);
  });

  testWidgets('a destination no bus reaches says so', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _openOptions(tester, from: _a, to: StopPlace(stopId: 'H', name: 'Stop H'));
    expect(find.text('No buses get you there at that time'), findsOneWidget);
    expect(find.byType(JourneyCard), findsNothing);
  });

  testWidgets('late at night, it names tomorrow\'s first bus', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: DateTime(testDay.year, testDay.month, testDay.day, 23));
    await _openOptions(tester, from: _a, to: _c);
    expect(find.text('No buses get you there at that time'), findsOneWidget);
    expect(find.text('The next bus that gets you there leaves tomorrow at 8:00 AM'), findsOneWidget);
  });

  testWidgets("leave by late on a later day names the day the next bus runs, not tomorrow", (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, textScale: 2);
    _container(tester).read(planQueryProvider.notifier)
      ..setFrom(_a)
      ..setTo(_c)
      ..setMode(PlanMode.leaveBy)
      ..setTime(DateTime(testDay.year, testDay.month, testDay.day + 2, 22));
    await _openOptions(tester);
    const message = 'The next bus that gets you there leaves on Sat, Oct 10 at 8:00 AM';
    await tester.scrollUntilVisible(find.text(message), 200, scrollable: _sheetList);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(find.text(message)).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a start far from every stop asks for a closer point', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _openOptions(tester, from: PinPlace(lat: 47.0, lon: -52.0, label: 'Pin'), to: _c);
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
    await _openOptions(tester, from: _a, to: _c);
    expect(find.text("Couldn't plan that trip"), findsOneWidget);
    expect(find.text('Try again in a moment.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the date button reads Today, then Tomorrow once tomorrow is picked', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _openOptions(tester);
    await tester.tap(find.text('Leave by'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, OptionsSheetContent.dateButtonKey), contains('Today'));
    await tester.tap(find.byKey(OptionsSheetContent.dateButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${testDay.day + 1}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, OptionsSheetContent.dateButtonKey), contains('Tomorrow'));
    final time = _container(tester).read(planQueryProvider).time!;
    // Leave by starts at 8:35 (8:01 + 30 min, rounded up); the date picker keeps that time of day.
    expect((time.day, time.hour, time.minute), (testDay.day + 1, 8, 35));
  });

  testWidgets('an Arrive by time never picked moves on with the clock, and the plan with it', (tester) async {
    var clock = _now;
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, clock: () => clock);
    await _openOptions(tester, from: _a, to: _c);
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    expect(_textIn(tester, OptionsSheetContent.timeButtonKey), contains('8:35')); // 8:01 + 30 min, rounded up
    bool arrivesAt840(PlanOutcome? o) => o is PlanFound && o.journeys.any((j) => j.arrives == 8 * 3600 + 40 * 60);
    expect(arrivesAt840(_container(tester).read(planResultsProvider).value), isFalse);

    clock = _now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(_textIn(tester, OptionsSheetContent.timeButtonKey), contains('8:40'));
    expect(_container(tester).read(planQueryProvider).time, isNull, reason: 'still not picked');
    expect(arrivesAt840(_container(tester).read(planResultsProvider).value), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the From row opens the search for the start; an empty start reads "Choose a start"', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    _container(tester).read(planQueryProvider.notifier).setDestination(_c);
    await _openOptions(tester);
    expect(_textIn(tester, OptionsSheetContent.fromRowKey), contains('Choose a start'));
    await _openFromSearch(tester);
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'A');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop A (A)'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(_container(tester).read(homeSheetProvider), isA<OptionsSheet>());
    expect(_textIn(tester, OptionsSheetContent.fromRowKey), contains('Stop A'));
  });

  testWidgets('tapping the destination opens the search to change it', (tester) async {
    await _openAtoC(tester);
    await tester.tap(find.byKey(OptionsSheetContent.toRowKey));
    await tester.pumpAndSettle();
    expect(tester.widget<SearchScreen>(find.byType(SearchScreen)).end, MapPick.to);
    expect(find.text('Where to?'), findsWidgets);
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'E');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop E (E)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(_container(tester).read(planQueryProvider).to, StopPlace(stopId: 'E', name: 'Stop E'));
    expect(_container(tester).read(planQueryProvider).from, _a, reason: 'the start is kept');
    expect(find.text('To Stop E'), findsOneWidget);
  });

  testWidgets('My location with location off says so and leaves the start empty', (tester) async {
    await _openAtoC(tester);
    _container(tester).read(planQueryProvider.notifier).setFrom(null);
    await tester.pumpAndSettle();
    await _openFromSearch(tester);
    await tester.tap(find.text('My location'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't find your location"), findsOneWidget);
    expect(find.byType(SearchScreen), findsOneWidget, reason: 'the rider can still pick a stop');
    expect(_container(tester).read(planQueryProvider).from, isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('My location fills the start with the phone\'s position', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, geolocator: FixedGeolocator(47.5601, -52.7501));
    _container(tester).read(planQueryProvider.notifier).setDestination(_c);
    await _openOptions(tester);
    await _openFromSearch(tester);
    await tester.tap(find.text('My location'));
    await tester.pumpAndSettle();
    final from = _container(tester).read(planQueryProvider).from;
    expect(from, isA<PinPlace>().having((p) => p.label, 'label', 'My location'));
    expect(_textIn(tester, OptionsSheetContent.fromRowKey), contains('My location'));
  });

  testWidgets('My location says it is finding you, and gives up after 10 s so it can be tried again', (tester) async {
    final handle = tester.ensureSemantics();
    final geo = NoFixGeolocator();
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, geolocator: geo);
    _container(tester).read(planQueryProvider.notifier).setDestination(_c);
    await _openOptions(tester);
    await _openFromSearch(tester);
    await tester.tap(find.text('My location'));
    await tester.pump();
    expect(find.text('Finding you…'), findsOneWidget);
    expect(find.bySemanticsLabel('Finding you…'), findsOneWidget);
    expect(geo.requests.single?.timeLimit, const Duration(seconds: 10));

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text("Couldn't find your location"), findsOneWidget);
    expect(find.text('Finding you…'), findsNothing);
    expect(_container(tester).read(planQueryProvider).from, isNull);

    await tester.tap(find.text('My location'));
    await tester.pump();
    expect(find.text('Finding you…'), findsOneWidget, reason: 'the row works again');
    expect(geo.requests, hasLength(2));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 4));
    handle.dispose();
  });

  testWidgets('at 2x text the finding-you row and the gave-up toast read in full', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, geolocator: NoFixGeolocator(), textScale: 2);
    _container(tester).read(planQueryProvider.notifier).setDestination(_c);
    await _openOptions(tester);
    await _openFromSearch(tester);
    await tester.tap(find.text('My location'));
    await tester.pump();
    expect(tester.renderObject<RenderParagraph>(find.text('Finding you…')).didExceedMaxLines, isFalse);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(tester.renderObject<RenderParagraph>(find.text("Couldn't find your location")).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
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

  testWidgets('the start\'s search lists the matching stops as "Name (id)"', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now);
    await _openOptions(tester);
    await _openFromSearch(tester);
    expect(find.text('Search for a stop or a place'), findsOneWidget);
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'stop');
    await tester.pumpAndSettle();
    expect(find.text('Stop A (A)'), findsOneWidget);
    expect(find.text('Stop B (B)'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Stop A (A)')).dy, lessThan(tester.getTopLeft(find.text('Stop B (B)')).dy));
  });

  testWidgets('Choose on map from the destination\'s search returns to the map to drop the pin', (tester) async {
    await _openAtoC(tester);
    await tester.tap(find.byKey(OptionsSheetContent.toRowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose on map'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(_container(tester).read(mapPickProvider), MapPick.to);
    expect(find.text('Tap the map to choose your destination'), findsOneWidget);
  });

  testWidgets('nothing overflows at 2x text, empty or with results', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, textScale: 2);
    await _openOptions(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Arrive by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(OptionsSheetContent.dateButtonKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Leave now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave now'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(OptionsSheetContent.fromRowKey));
    await tester.pumpAndSettle();
    await _openFromSearch(tester);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'A');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop A (A)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(OptionsSheetContent.toRowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(OptionsSheetContent.toRowKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'C');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop C (C)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _pullUp(tester);
    await tester.scrollUntilVisible(find.byType(JourneyCard).last, 200, scrollable: _sheetList);
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
      await _openOptions(tester);
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
    await _openOptions(tester);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.bySemanticsLabel('From: not chosen'), findsOneWidget);
    expect(find.bySemanticsLabel('Destination, not chosen. Change'), findsOneWidget);
    expect(find.bySemanticsLabel('Swap start and destination'), findsOneWidget);
    for (final s in ['Leave now', 'Leave by', 'Arrive by']) {
      expect(find.bySemanticsLabel(s), findsOneWidget);
    }
    _container(tester).read(planQueryProvider.notifier).setTrip(_a, _c);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('From: Stop A'), findsOneWidget);
    expect(find.bySemanticsLabel('Destination, Stop C. Change'), findsOneWidget);
    expect(tester.getSemantics(find.byType(JourneyCard).first).label, contains('Leave 8:10'));
    await tester.tap(find.text('Leave by'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Time, ')), findsOneWidget);
    expect(find.bySemanticsLabel('Date, Today'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping a journey opens its steps in the sheet and draws it', (tester) async {
    await _openAtoC(tester);
    await tester.tap(find.byType(JourneyCard).first);
    await tester.pumpAndSettle();
    final c = _container(tester);
    final sheet = c.read(homeSheetProvider);
    expect(sheet, isA<JourneySheet>());
    expect(c.read(journeyOnMapProvider), same((sheet as JourneySheet).journey));
    expect(find.text('Your trip'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is RouteBadge && w.label == '1'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^8:10\b.*→ 8:20\b')), findsOneWidget);
  });

  testWidgets('back from a journey returns to options, and back again clears the map and goes home', (tester) async {
    await _openAtoC(tester);
    await tester.tap(find.byType(JourneyCard).first);
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    expect(c.read(homeSheetProvider), isA<JourneySheet>());
    await tester.tap(find.bySemanticsLabel('Back').first);
    await tester.pumpAndSettle();
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    final first = (c.read(planResultsProvider).value! as PlanFound).journeys.first;
    expect(c.read(journeyOnMapProvider), _sameTripAs(first), reason: 'the first journey is drawn again');
    await tester.tap(find.bySemanticsLabel('Back').first);
    await tester.pumpAndSettle();
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    expect(c.read(journeyOnMapProvider), isNull);
  });

  testWidgets('system back from options also clears the drawn trip', (tester) async {
    await _openAtoC(tester);
    final c = _container(tester);
    expect(c.read(journeyOnMapProvider), isNotNull);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    expect(c.read(journeyOnMapProvider), isNull);
  });

  testWidgets('a tap on empty map with options open only lowers the sheet (Ruling 13)', (tester) async {
    final map = StubMap();
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, mapView: map.build);
    await _openOptions(tester, from: _a, to: _c);
    final c = _container(tester);
    final before = tester.getRect(find.byKey(BBSheet.cardKey)).top;
    map.tap(47.0, -52.0); // far from every stop
    await tester.pumpAndSettle();
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(c.read(journeyOnMapProvider), isNotNull);
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, greaterThan(before), reason: 'back to peek');

    c.read(homeSheetProvider.notifier).open(JourneySheet((c.read(planResultsProvider).value! as PlanFound).journeys.first));
    await tester.pumpAndSettle();
    map.tap(47.0, -52.0);
    await tester.pumpAndSettle();
    expect(c.read(homeSheetProvider), isA<JourneySheet>());
  });

  testWidgets('★ Save trip saves the options\' ends', (tester) async {
    await _openAtoC(tester);
    await tester.scrollUntilVisible(find.text('Save trip'), 200, scrollable: _sheetList);
    await tester.pumpAndSettle();
    expect(find.byIcon(BBIcons.starOutline), findsOneWidget);
    await tester.tap(find.text('Save trip'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(BBIcons.star), findsOneWidget, reason: 'the star fills once saved');
    final trips = _container(tester).read(savedTripsProvider).value!;
    expect(trips.map((t) => (t.name, t.from, t.to)), [('Stop A → Stop C', _a, _c)]);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('choosing the destination on the map', (tester) async {
    final map = StubMap();
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/', mapView: map.build);
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    c.read(mapPickProvider.notifier).start(MapPick.to);
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to choose your destination'), findsOneWidget);
    map.tap(47.5700, -52.7500); // Stop C in the test network
    await tester.pumpAndSettle();
    expect(c.read(mapPickProvider), isNull);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(c.read(planQueryProvider).to, isA<StopPlace>());
  });
}

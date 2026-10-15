import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/trip_planner/journey_card.dart';
import 'package:busboard_nl/ui/trip_planner/saved_trips_section.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/live_overlay_test.dart' show feedWith;
import '../trip_planner/test_network.dart';

DateTime _at(int h, int m) =>
    DateTime(testDay.year, testDay.month, testDay.day, h, m);

final _aToC = SavedTrip(
  id: 't1',
  name: 'Stop A → Stop C',
  from: StopPlace(stopId: 'A', name: 'Stop A'),
  to: StopPlace(stopId: 'C', name: 'Stop C'),
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

/// Opens home at [now] with [trips] saved, its sheet pulled up to the saved trips.
Future<void> _pump(
  WidgetTester tester, {
  DateTime? now,
  double textScale = 1,
  List<SavedTrip>? trips,
  List<Override> overrides = const [],
  Size size = const Size(390, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpPlannerApp(
    tester,
    net: TestNetwork(),
    now: now ?? _at(8, 1),
    textScale: textScale,
    overrides: overrides,
  );
  final saved = _container(tester).read(savedTripsProvider.notifier);
  for (final t in trips ?? [_aToC]) {
    await saved.add(t);
  }
  await tester.pumpAndSettle();
  await tester.drag(find.byKey(BBSheet.handleKey), const Offset(0, -600));
  await tester.pumpAndSettle();
}

Finder get _more => find.byKey(SavedTripsSection.moreKey(_aToC.id));

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'the card shows the name and the next departures, the first with its route',
    (tester) async {
      await _pump(tester);
      expect(find.text('Saved trips'), findsOneWidget);
      expect(find.text('Stop A → Stop C'), findsOneWidget);
      expect(find.text('8:10 · 1'), findsOneWidget);
      expect(find.text('8:20, 8:30'), findsOneWidget);
    },
  );

  testWidgets('tapping the card fills From and To and opens the trip options', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(JourneyCard), findsNothing);
    await tester.tap(find.text('Stop A → Stop C'));
    await tester.pumpAndSettle();
    final draft = _container(tester).read(planQueryProvider);
    expect(draft.from, StopPlace(stopId: 'A', name: 'Stop A'));
    expect(draft.to, StopPlace(stopId: 'C', name: 'Stop C'));
    expect(draft.mode, PlanMode.leaveNow);
    expect(_container(tester).read(homeSheetProvider), isA<OptionsSheet>());
    expect(find.byType(JourneyCard), findsWidgets);
  });

  testWidgets('More offers Rename; the new name is shown and kept', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Work');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Stop A → Stop C'), findsNothing);
    expect(
      _container(tester).read(savedTripsProvider).value!.single.name,
      'Work',
    );
  });

  testWidgets('the Trip name field keeps a visible label once the user types', (tester) async {
    await _pump(tester);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Work');
    await tester.pump();
    // The hint is faded out in place, so look for a 'Trip name' that is not inside the field.
    final labels = find.text('Trip name').evaluate().where((e) => e.findAncestorWidgetOfExactType<BBTextField>() == null);
    expect(labels, hasLength(1), reason: 'the label stays above the field once the hint is gone');
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('a screen reader hears the Trip name field once, not again from its visual caption', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();
    expect(find.text('Trip name'), findsNWidgets(2), reason: 'the caption and the hint are both drawn');
    final said = <SemanticsData>[];
    void walk(SemanticsNode node) {
      final d = node.getSemanticsData();
      if ([d.label, d.hint, d.value].contains('Trip name')) said.add(d);
      node.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(tester.binding.renderViews.single.debugSemantics!);
    expect(said, hasLength(1));
    expect(said.single.flagsCollection.isTextField, isTrue, reason: 'it is the field that carries the label');
    handle.dispose();
  });

  testWidgets('long-pressing the card opens the same dialog', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('Stop A → Stop C'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    // A long-press doesn't also open the plan.
    expect(_container(tester).read(planQueryProvider).from, isNull);
    expect(_container(tester).read(homeSheetProvider), isA<HomeSheetHome>());
  });

  testWidgets(
    'an empty name keeps the old one; a long name is cut to 40 characters',
    (tester) async {
      await _pump(tester);
      await tester.tap(_more);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), '   ');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Stop A → Stop C'), findsOneWidget);

      await tester.tap(_more);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'x' * 60);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(
        _container(tester).read(savedTripsProvider).value!.single.name,
        'x' * 40,
      );
    },
  );

  testWidgets('Cancel leaves the name alone', (tester) async {
    await _pump(tester);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Work');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Stop A → Stop C'), findsOneWidget);
  });

  testWidgets(
    'Remove asks first; Cancel keeps the trip, Remove deletes it and the header goes',
    (tester) async {
      await _pump(tester);
      await tester.tap(_more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this saved trip?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Stop A → Stop C'), findsOneWidget);

      await tester.tap(_more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Stop A → Stop C'), findsNothing);
      expect(find.text('Saved trips'), findsNothing);
      expect(_container(tester).read(savedTripsProvider).value, isEmpty);
    },
  );

  testWidgets('with nothing saved the section shows nothing', (tester) async {
    await _pump(tester, trips: const []);
    expect(find.text('Saved trips'), findsNothing);
  });

  testWidgets('while the departures load the card shows a skeleton line', (
    tester,
  ) async {
    await _pump(tester);
    // A fresh plan is not instant: pump the first frames of a new card.
    final pending = _container(tester).read(savedTripsProvider.notifier);
    await pending.add(
      SavedTrip(
        id: 't2',
        name: 'Second',
        from: StopPlace(stopId: 'B', name: 'Stop B'),
        to: StopPlace(stopId: 'C', name: 'Stop C'),
      ),
    );
    await tester.pump();
    expect(find.byType(BBSkeleton), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(BBSkeleton), findsNothing);
  });

  testWidgets('late at night the card says there are no more buses today', (
    tester,
  ) async {
    await _pump(tester, now: _at(22, 0));
    expect(find.text('No more buses today'), findsOneWidget);
  });

  testWidgets('screen readers hear the name, the next time and its route', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(
      find.bySemanticsLabel(
        'Saved trip Stop A → Stop C, next bus 8:10, route 1',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('More, Stop A → Stop C'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('screen readers hear when there are no more buses', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, now: _at(22, 0));
    expect(
      find.bySemanticsLabel('Saved trip Stop A → Stop C, no more buses today'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets(
    'at 2x text nothing overflows or is cut short, on the card and in the dialogs',
    (tester) async {
      await _pump(tester, textScale: 2, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
      for (final text in [
        'Saved trips',
        'Stop A → Stop C',
        '8:10 · 1',
        '8:20, 8:30',
      ]) {
        await tester.ensureVisible(find.text(text));
        await tester.pumpAndSettle();
        final p = tester.renderObject<RenderParagraph>(find.text(text));
        expect(p.didExceedMaxLines, isFalse, reason: '"$text" is cut short');
      }
      await tester.ensureVisible(_more);
      await tester.pumpAndSettle();
      await tester.tap(_more);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this saved trip?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a bus running 2 minutes late shows its live time, "live", and says so aloud', (tester) async {
    final handle = tester.ensureSemantics();
    final net = TestNetwork();
    final feed = feedWith(net, {'1-1': 120}, _at(8, 1));
    await _pump(tester, overrides: [plannerLiveFeedProvider.overrideWith((ref) async => feed)]);
    expect(find.text('8:12 · 1 · live'), findsOneWidget);
    expect(find.text('8:20, 8:30'), findsOneWidget);
    expect(find.bySemanticsLabel('Saved trip Stop A → Stop C, next bus 8:12, route 1, live'), findsOneWidget);
    final text = tester.widget<Text>(find.text('8:12 · 1 · live'));
    expect(text.style?.color, BBColors.light.liveInk);
    handle.dispose();
  });

  test('departures are distinct, earliest first, three at most', () {
    final day = DateTime(2026, 10, 8);
    Journey j(String trip, int departs) => Journey(serviceDate: day, legs: [
          RideLeg(
            routeId: '1',
            tripId: trip,
            boardStopId: 'A',
            alightStopId: 'C',
            departs: departs,
            arrives: departs + 600,
            stopCount: 2,
          ),
        ]);
    final out = savedTripDepartures([
      j('b', 29400),
      j('a', 29400 - 600),
      j('b', 29400), // the same bus again (a different second leg)
      j('c', 29400), // another bus at the same minute
      j('d', 29400 + 600),
      j('e', 29400 + 1200),
    ]);
    expect(out.map((d) => d.ride.tripId), ['a', 'b', 'd']);
    expect(out.map((d) => d.time.hour * 60 + d.time.minute), [480, 490, 500]);
  });

  test('two routes leaving at the same minute both stay', () {
    final day = DateTime(2026, 10, 8);
    Journey j(String trip, String route, int departs) => Journey(serviceDate: day, legs: [
          RideLeg(
            routeId: route,
            tripId: trip,
            boardStopId: 'A',
            alightStopId: 'C',
            departs: departs,
            arrives: departs + 600,
            stopCount: 2,
          ),
        ]);
    final out = savedTripDepartures([j('a', '1', 29400), j('b', '2', 29400), j('c', '2', 29400)]);
    expect(out.map((d) => d.ride.tripId), ['a', 'b']);
  });

  testWidgets('the card lists distinct times, earliest first, three at most, from journeys that repeat and run out of order',
      (tester) async {
    Journey j(String trip, int departs) => Journey(serviceDate: testDay, legs: [
          RideLeg(
            routeId: '1',
            tripId: trip,
            boardStopId: 'A',
            alightStopId: 'C',
            departs: departs,
            arrives: departs + 600,
            stopCount: 2,
          ),
        ]);
    final handle = tester.ensureSemantics();
    final journeys = [
      j('b', 8 * 3600 + 1200), // 8:20
      j('a', 8 * 3600 + 600), // 8:10
      j('b', 8 * 3600 + 1200), // 8:20 again, with another second leg
      j('c', 8 * 3600 + 1800), // 8:30
      j('d', 8 * 3600 + 2400), // 8:40
    ];
    await _pump(tester, overrides: [savedTripNextProvider(_aToC.id).overrideWith((ref) async => journeys)]);
    expect(find.text('8:10 · 1'), findsOneWidget);
    expect(find.text('8:20, 8:30'), findsOneWidget);
    expect(find.textContaining('8:40'), findsNothing);
    expect(find.bySemanticsLabel('Saved trip Stop A → Stop C, next bus 8:10, route 1'), findsOneWidget);
    handle.dispose();
  });
}

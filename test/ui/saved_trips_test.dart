import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/trip_planner/journey_card.dart';
import 'package:busboard_nl/ui/trip_planner/plan_screen.dart';
import 'package:busboard_nl/ui/trip_planner/saved_trips_section.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
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
    ProviderScope.containerOf(tester.element(find.byType(PlanScreen)));

/// Opens the Plan tab at [now] with [trips] saved.
Future<void> _pump(
  WidgetTester tester, {
  DateTime? now,
  double textScale = 1,
  List<SavedTrip>? trips,
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
  );
  final saved = _container(tester).read(savedTripsProvider.notifier);
  for (final t in trips ?? [_aToC]) {
    await saved.add(t);
  }
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

  testWidgets('tapping the card fills From and To and shows the plan', (
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

  testWidgets('long-pressing the card opens the same dialog', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('Stop A → Stop C'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    // A long-press doesn't also open the plan.
    expect(_container(tester).read(planQueryProvider).from, isNull);
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
}

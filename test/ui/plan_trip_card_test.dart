import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/stop_picker/plan_trip_card.dart';
import 'package:busboard_nl/ui/stop_picker/stop_picker_screen.dart';
import 'package:busboard_nl/ui/trip_planner/journey_card.dart';
import 'package:busboard_nl/ui/trip_planner/journey_detail_screen.dart';
import 'package:busboard_nl/ui/trip_planner/plan_screen.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

DateTime _at(int h, int m) => DateTime(testDay.year, testDay.month, testDay.day, h, m);

SavedTrip _trip(String id, String from, String to) => SavedTrip(
      id: id,
      name: 'Stop $from → Stop $to',
      from: StopPlace(stopId: from, name: 'Stop $from'),
      to: StopPlace(stopId: to, name: 'Stop $to'),
    );

final _aToC = _trip('t1', 'A', 'C');
final _bToC = _trip('t2', 'B', 'C');
final _cToE = _trip('t3', 'C', 'E');
final _aToE = _trip('t4', 'A', 'E');

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(StopPickerScreen, skipOffstage: false)));

final _header = find.byKey(PlanTripCard.headerKey);
final _all = find.byKey(PlanTripCard.allKey);
Finder _line(SavedTrip t) => find.byKey(PlanTripCard.tripKey(t.id));

/// The Board tab's stop picker at [now], with [trips] saved and [lastStop] as the last stop.
Future<void> _pump(
  WidgetTester tester, {
  DateTime? now,
  List<SavedTrip> trips = const [],
  String? lastStop,
  Size size = const Size(390, 1400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpPlannerApp(tester, net: TestNetwork(), now: now ?? _at(8, 1), initial: '/', textScale: textScale);
  final c = _container(tester);
  if (lastStop != null) await c.read(settingsProvider.notifier).setSelectedStop(lastStop);
  for (final t in trips) {
    await c.read(savedTripsProvider.notifier).add(t);
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('where the card sits', () {
    testWidgets('directly under the Last stop card, above the stop number field', (tester) async {
      await _pump(tester, lastStop: 'A');
      expect(find.text('Plan a trip'), findsOneWidget);
      expect(find.text('Leave or arrive by any time'), findsOneWidget);
      final last = tester.getRect(find.ancestor(of: find.text('Last stop'), matching: find.byType(BBCard)));
      final card = tester.getRect(find.byType(PlanTripCard));
      final entry = tester.getRect(find.text('Stop number on the pole'));
      expect(card.top, greaterThan(last.bottom));
      expect(card.top - last.bottom, lessThanOrEqualTo(BBSpace.xl), reason: 'right under it, nothing between');
      expect(card.bottom, lessThan(entry.top));
    });

    testWidgets('at the top when there is no last stop', (tester) async {
      await _pump(tester);
      expect(find.text('Last stop'), findsNothing);
      final title = tester.getRect(find.text('Choose a stop'));
      final card = tester.getRect(find.byType(PlanTripCard));
      final entry = tester.getRect(find.text('Stop number on the pole'));
      expect(card.top, greaterThan(title.bottom));
      expect(card.bottom, lessThan(entry.top), reason: 'the first thing under the header');
    });

    testWidgets('it has the Last stop card\'s look: a tinted plan tile, title, muted subtitle and a chevron',
        (tester) async {
      await _pump(tester);
      final tile = tester.widget<BBIconTile>(find.descendant(of: _header, matching: find.byType(BBIconTile)));
      expect(tile.icon, BBIcons.plan);
      expect(find.descendant(of: _header, matching: find.byIcon(BBIcons.chevronRight)), findsOneWidget);
      final subtitle = tester.widget<Text>(find.text('Leave or arrive by any time'));
      expect(subtitle.style?.color, BBColors.light.muted);
    });
  });

  group('tapping the header opens the planner, as the Plan button does', () {
    testWidgets('the Plan page opens, and back returns to the picker', (tester) async {
      await _pump(tester);
      await tester.tap(_header);
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(StopPickerScreen), findsOneWidget);
    });

    testWidgets('a quick double tap opens one page', (tester) async {
      await _pump(tester);
      await tester.tap(_header);
      await tester.tap(_header);
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen, skipOffstage: false), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(StopPickerScreen), findsOneWidget, reason: 'one back was enough');
    });

    testWidgets("a trip whose steps were left open comes back over the planner", (tester) async {
      await _pump(tester);
      final journey = Journey(serviceDate: testDay, legs: [
        RideLeg(routeId: '1', tripId: '1-1', boardStopId: 'A', alightStopId: 'C', departs: 8 * 3600 + 600,
            arrives: 8 * 3600 + 1200, stopCount: 2),
      ]);
      _container(tester).read(openJourneyProvider.notifier).open(journey);
      await tester.tap(_header);
      await tester.pumpAndSettle();
      expect(find.byType(JourneyDetailScreen), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsOneWidget, reason: 'over the planner');
    });
  });

  group('saved trips', () {
    testWidgets('with none saved the card is just its header line', (tester) async {
      await _pump(tester);
      expect(find.byType(PlanTripCard), findsOneWidget);
      expect(find.textContaining('→'), findsNothing);
      expect(_all, findsNothing);
      expect(find.text('All saved trips'), findsNothing);
    });

    testWidgets('each is a line with its next bus at the right', (tester) async {
      await _pump(tester, trips: [_aToC]);
      expect(find.descendant(of: find.byType(PlanTripCard), matching: find.text('Stop A → Stop C')), findsOneWidget);
      expect(find.descendant(of: _line(_aToC), matching: find.text('8:10 AM')), findsOneWidget);
      final name = tester.getRect(find.text('Stop A → Stop C'));
      final next = tester.getRect(find.text('8:10 AM'));
      expect(next.left, greaterThan(name.right), reason: 'at the right');
      expect(_all, findsNothing);
    });

    testWidgets('three at most, then "All saved trips"', (tester) async {
      await _pump(tester, trips: [_aToC, _bToC, _cToE, _aToE]);
      expect(_line(_aToC), findsOneWidget);
      expect(_line(_bToC), findsOneWidget);
      expect(_line(_cToE), findsOneWidget);
      expect(_line(_aToE), findsNothing);
      expect(find.text('Stop A → Stop E'), findsNothing);
      expect(find.descendant(of: _all, matching: find.text('All saved trips')), findsOneWidget);
      expect(tester.getRect(_all).top, greaterThanOrEqualTo(tester.getRect(_line(_cToE)).bottom), reason: 'last');
    });

    testWidgets('exactly three: no "All saved trips"', (tester) async {
      await _pump(tester, trips: [_aToC, _bToC, _cToE]);
      expect(_line(_cToE), findsOneWidget);
      expect(_all, findsNothing);
    });

    testWidgets('"All saved trips" opens the planner', (tester) async {
      await _pump(tester, trips: [_aToC, _bToC, _cToE, _aToE]);
      await tester.tap(_all);
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsOneWidget);
      expect(find.text('Stop A → Stop E'), findsOneWidget, reason: "the planner's own list has them all");
      expect(_container(tester).read(planQueryProvider).from, isNull, reason: 'nothing planned');
    });

    testWidgets('tapping a trip opens the planner with that trip planned', (tester) async {
      await _pump(tester, trips: [_aToC, _cToE]);
      await tester.tap(_line(_cToE));
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsOneWidget);
      final draft = _container(tester).read(planQueryProvider);
      expect(draft.from, StopPlace(stopId: 'C', name: 'Stop C'));
      expect(draft.to, StopPlace(stopId: 'E', name: 'Stop E'));
      expect(draft.mode, PlanMode.leaveNow);
      expect(find.byType(JourneyCard), findsWidgets);
    });

    testWidgets('a trip tap is a new plan: a trip left open does not come back over it', (tester) async {
      await _pump(tester, trips: [_aToC]);
      final journey = Journey(serviceDate: testDay, legs: [
        RideLeg(routeId: '2', tripId: '2-1', boardStopId: 'C', alightStopId: 'E', departs: 8 * 3600 + 1200,
            arrives: 8 * 3600 + 1680, stopCount: 2),
      ]);
      _container(tester).read(openJourneyProvider.notifier).open(journey);
      await tester.tap(_line(_aToC));
      await tester.pumpAndSettle();
      expect(find.byType(JourneyDetailScreen), findsNothing);
      expect(find.byType(PlanScreen), findsOneWidget);
      expect(_container(tester).read(openJourneyProvider), isNull);
    });

    testWidgets('a quick double tap on a trip opens one planner', (tester) async {
      await _pump(tester, trips: [_aToC]);
      await tester.tap(_line(_aToC));
      await tester.tap(_line(_aToC));
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen, skipOffstage: false), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(StopPickerScreen), findsOneWidget);
    });

    testWidgets('late at night a trip says there are no more buses today', (tester) async {
      await _pump(tester, now: _at(22, 0), trips: [_aToC]);
      expect(find.descendant(of: _line(_aToC), matching: find.text('No more buses today')), findsOneWidget);
    });
  });

  group('screen readers', () {
    testWidgets('the header reads its title and subtitle, as one button', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(
        tester.getSemantics(_header),
        isSemantics(label: 'Plan a trip. Leave or arrive by any time', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('a trip line reads its name and next bus', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, trips: [_aToC, _bToC, _cToE, _aToE]);
      expect(
        tester.getSemantics(_line(_aToC)),
        isSemantics(label: 'Saved trip Stop A to Stop C, next bus 8:10 AM', isButton: true, hasTapAction: true),
      );
      expect(tester.getSemantics(_all), isSemantics(label: 'All saved trips', isButton: true, hasTapAction: true));
      handle.dispose();
    });

    testWidgets('and when there are no more buses', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, now: _at(22, 0), trips: [_aToC]);
      expect(tester.getSemantics(_line(_aToC)).label, 'Saved trip Stop A to Stop C, no more buses today');
      handle.dispose();
    });

    testWidgets('every target is at least 44 pt tall and wide', (tester) async {
      await _pump(tester, trips: [_aToC, _bToC, _cToE, _aToE]);
      for (final f in [_header, _line(_aToC), _line(_bToC), _line(_cToE), _all]) {
        final size = tester.getSize(f);
        expect(size.height, greaterThanOrEqualTo(44), reason: '$f');
        expect(size.width, greaterThanOrEqualTo(44), reason: '$f');
      }
    });
  });

  group('large text', () {
    /// The text is laid out at its full width: not cut, ellipsised or broken inside a word.
    void readsInFull(WidgetTester tester, Finder text) {
      final p = tester.renderObject<RenderParagraph>(text);
      expect(p.size.width, greaterThanOrEqualTo(p.getMinIntrinsicWidth(double.infinity) - 0.5), reason: '$text');
      expect(p.didExceedMaxLines, isFalse, reason: '$text');
    }

    for (final size in [const Size(360, 780), const Size(320, 568)]) {
      testWidgets('at 2x text on ${size.width.toInt()} dp nothing overflows or is cut short', (tester) async {
        await _pump(tester, size: size, textScale: 2, lastStop: 'A', trips: [_aToC, _bToC, _cToE, _aToE]);
        expect(tester.takeException(), isNull);
        for (final f in [
          find.text('Plan a trip'),
          find.text('Leave or arrive by any time'),
          find.text('Stop A → Stop C'),
          find.descendant(of: _line(_aToC), matching: find.text('8:10 AM')),
          find.text('All saved trips'),
        ]) {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          readsInFull(tester, f);
        }
        for (final f in [_header, _line(_aToC), _all]) {
          expect(tester.getSize(f).height, greaterThanOrEqualTo(44));
        }
      });
    }
  });
}

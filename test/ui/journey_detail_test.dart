import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/journey_on_map_provider.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_screen.dart';
import 'package:busboard_nl/ui/trip_planner/journey_detail_screen.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/feed_fixtures.dart';
import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/live_overlay_test.dart' show feedWith;
import '../trip_planner/test_network.dart';

DateTime _at(int h, int m) => DateTime(testDay.year, testDay.month, testDay.day, h, m);

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(BBNavBar)));

String _location(WidgetTester tester) => GoRouter.of(tester.element(find.byType(BBNavBar))).state.uri.toString();

Finder _badge(String route) => find.byWidgetPredicate((w) => w is RouteBadge && w.label == route);

/// Plans Stop A → Stop E and opens the journey leaving A at 8:00.
Future<void> _openAtoE(
  WidgetTester tester, {
  DateTime? now,
  double textScale = 1,
  List<Override> overrides = const [],
}) async {
  await pumpPlannerApp(tester, net: TestNetwork(), now: now ?? _at(8, 0), textScale: textScale, overrides: overrides);
  _container(tester).read(planQueryProvider.notifier)
    ..setFrom(StopPlace(stopId: 'A', name: 'Stop A'))
    ..setTo(StopPlace(stopId: 'E', name: 'Stop E'));
  await tester.pumpAndSettle();
  final card = find.text('8:00 AM → 8:28 AM');
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
  expect(find.byType(JourneyDetailScreen), findsOneWidget);
}

const _brokenWarning = 'This trip no longer works with live times. Go back for updated options.';

/// A live feed a test can change: set [feed], then [refresh] as the 30 s poll would.
class _Feed {
  TimeTrackFetchResult? feed;
  Override get override => plannerLiveFeedProvider.overrideWith((ref) async => feed);
  Future<void> refresh(WidgetTester tester, TimeTrackFetchResult? next) async {
    feed = next;
    _container(tester).invalidate(plannerLiveFeedProvider);
    await tester.pumpAndSettle();
  }
}

/// Keeps what the Board-style refresh hands the alert controller.
class _RecordingAlerts extends ArrivalAlertController {
  final calls = <(String, List<ArrivalRow>)>[];
  @override
  Future<ArrivalAlert?> build() async => null;
  @override
  void onBoardArrivals(String stopId, List<ArrivalRow> rows) => calls.add((stopId, rows));
}

/// Lets the real map tab's timers run out once it is gone.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the detail lists the legs of A → E in order, then the arrival', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openAtoE(tester);
    expect(find.text('Your trip'), findsOneWidget);
    expect(find.text('Leave 8:00 AM · arrive 8:28 AM'), findsOneWidget);
    final firstRide = find.textContaining(RegExp(r'^8:00 AM → 8:10 AM\b'));
    final secondRide = find.textContaining(RegExp(r'^8:20 AM → 8:28 AM\b'));
    // Each badge leads its own ride's line.
    expect(tester.getTopLeft(_badge('1')).dy, tester.getTopLeft(firstRide).dy);
    expect(tester.getTopLeft(_badge('2')).dy, tester.getTopLeft(secondRide).dy);
    final inOrder = [firstRide, secondRide, find.text('Arrive 8:28 AM')];
    var last = double.negativeInfinity;
    for (final f in inOrder) {
      expect(f, findsOneWidget);
      final y = tester.getTopLeft(f).dy;
      expect(y, greaterThan(last), reason: '$f is out of order');
      last = y;
    }
    expect(find.text('8:00 AM → 8:10 AM · 2 stops'), findsOneWidget);
    expect(find.text('Get on at Stop A (A)'), findsOneWidget);
    expect(find.text('Get off at Stop C (C)'), findsOneWidget);
  });

  testWidgets('Save trip says Saved, then Already saved, and keeps one trip named by its ends', (tester) async {
    await _openAtoE(tester);
    expect(find.byIcon(BBIcons.starOutline), findsOneWidget);
    await tester.ensureVisible(find.text('Save trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save trip'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(BBIcons.star), findsOneWidget, reason: 'the star fills once saved');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save trip'));
    await tester.pumpAndSettle();
    expect(find.text('Already saved'), findsOneWidget);
    final trips = _container(tester).read(savedTripsProvider).value!;
    expect(trips.map((t) => t.name), ['Stop A → Stop E']);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('with 10 trips saved, Save trip says the list is full and adds nothing', (tester) async {
    await _openAtoE(tester);
    final saved = _container(tester).read(savedTripsProvider.notifier);
    for (var i = 0; i < maxSavedTrips; i++) {
      await saved.add(SavedTrip(
            id: '$i',
            name: 'Trip $i',
            from: StopPlace(stopId: 'B', name: 'Stop B'),
            to: StopPlace(stopId: 'X$i', name: 'Stop X$i'),
          ));
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save trip'));
    await tester.pumpAndSettle();
    expect(find.text('You can save up to 10 trips'), findsOneWidget);
    expect(_container(tester).read(savedTripsProvider).value, hasLength(maxSavedTrips));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Show on map puts the journey on the map and shows the Map tab', (tester) async {
    await _openAtoE(tester);
    await tester.ensureVisible(find.text('Show on map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show on map'));
    await tester.pumpAndSettle();
    final shown = _container(tester).read(journeyOnMapProvider);
    expect(shown, isNotNull);
    expect(shown!.departs, 8 * 3600);
    expect(_location(tester), '/map');
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Hide the trip from the map'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a bus 10 minutes out offers the bell on the first ride; with no live bus there is no Follow', (
    tester,
  ) async {
    await _openAtoE(tester, now: _at(7, 50));
    expect(find.bySemanticsLabel('Alert me before route 1 arrives'), findsOneWidget);
    expect(find.bySemanticsLabel('Alert me before route 2 arrives'), findsNothing, reason: 'first ride only');
    expect(find.text('Follow bus'), findsNothing);
  });

  testWidgets('a live bus on the first ride can be followed on the map', (tester) async {
    final now = _at(7, 50);
    await _openAtoE(
      tester,
      now: now,
      overrides: [
        plannerLiveFeedProvider.overrideWith((ref) async => fakeFeed([fakeVehicle(trip: '1-0', id: '1415', diff: 0, fix: now)])),
      ],
    );
    await tester.ensureVisible(find.text('Follow bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow bus'));
    await tester.pumpAndSettle();
    expect(_container(tester).read(followProvider), const FollowTarget('1415'));
    expect(_location(tester), '/map');
    await _unmount(tester);
  });

  testWidgets('a live delay on the first ride moves the detail\'s times, with the Live pill', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final live = _Feed();
    await _openAtoE(tester, overrides: [live.override]);
    expect(find.text('8:00 AM → 8:10 AM · 2 stops'), findsOneWidget);
    expect(find.text('Live'), findsNothing);

    await live.refresh(tester, feedWith(TestNetwork(), {'1-0': 120}, _at(8, 0)));
    expect(find.byType(JourneyDetailScreen), findsOneWidget);
    expect(find.text('8:02 AM → 8:12 AM · 2 stops'), findsOneWidget);
    expect(find.text('Leave 8:02 AM · arrive 8:28 AM'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text(_brokenWarning), findsNothing, reason: 'eight minutes is still enough to change at C');
  });

  testWidgets('a delay that leaves no time to change says the trip no longer works, as a live region', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final live = _Feed();
    await _openAtoE(tester, overrides: [live.override]);
    expect(find.text(_brokenWarning), findsNothing);

    // 1-0 ten minutes late reaches C at 8:20, as 2-1 leaves.
    await live.refresh(tester, feedWith(TestNetwork(), {'1-0': 600}, _at(8, 0)));
    expect(find.text('8:10 AM → 8:20 AM · 2 stops'), findsOneWidget);
    expect(find.text(_brokenWarning), findsOneWidget);
    expect(find.semantics.byLabel(_brokenWarning), isSemantics(isLiveRegion: true, label: _brokenWarning));

    await live.refresh(tester, feedWith(TestNetwork(), {'1-0': 0}, _at(8, 0)));
    expect(find.text(_brokenWarning), findsNothing, reason: 'back on time, the trip works again');
    handle.dispose();
  });

  testWidgets('each refresh hands the first ride\'s row to the alert controller, as the Board does', (tester) async {
    final alerts = _RecordingAlerts();
    final live = _Feed();
    await _openAtoE(
      tester,
      now: _at(7, 50),
      overrides: [live.override, arrivalAlertProvider.overrideWith(() => alerts)],
    );
    expect(alerts.calls, isNotEmpty, reason: 'once on opening');
    final (stopId, rows) = alerts.calls.last;
    expect(stopId, 'A');
    expect(rows.single.tripId, '1-0');

    final before = alerts.calls.length;
    await live.refresh(tester, feedWith(TestNetwork(), {'1-0': 120}, _at(7, 50)));
    expect(alerts.calls.length, greaterThan(before));
    final (_, liveRows) = alerts.calls.last;
    expect((liveRows.single.tripId, liveRows.single.isLive), ('1-0', true));
  });

  testWidgets('at 2x text on 320x568 the broken-trip warning reads in full', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final live = _Feed();
    await _openAtoE(tester, overrides: [live.override], textScale: 2);
    await live.refresh(tester, feedWith(TestNetwork(), {'1-0': 600}, _at(8, 0)));
    await tester.ensureVisible(find.text(_brokenWarning));
    await tester.pumpAndSettle();
    expect(tester.renderObject<RenderParagraph>(find.text(_brokenWarning)).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(320, 568), Size(390, 844)]) {
    testWidgets('at 2x text on ${size.width.toInt()}x${size.height.toInt()} the detail neither overflows nor cuts text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openAtoE(tester, now: _at(7, 50), textScale: 2);
      expect(tester.takeException(), isNull);
      final list = find.descendant(of: find.byType(JourneyDetailScreen), matching: find.byType(Scrollable)).first;
      void checkText() {
        for (final p in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: find.byType(JourneyDetailScreen), matching: find.byType(RichText)),
        )) {
          expect(p.didExceedMaxLines, isFalse, reason: '"${p.text.toPlainText()}" is cut short');
        }
      }

      checkText();
      await tester.scrollUntilVisible(find.text('Save trip'), 200, scrollable: list);
      await tester.pumpAndSettle();
      checkText();
      expect(tester.takeException(), isNull);
    });
  }
}

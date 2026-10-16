import 'dart:async';
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_tip.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/ui/home/options_sheet.dart';
import 'package:busboard_nl/ui/search/search_screen.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/stop_picker/near_me_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_alerts.dart';
import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

final _now = DateTime(2026, 10, 12, 13, 0);

/// TestNetwork stop C is served by route 1 (which ends there) and route 2 (which starts there).
const _stopC = StopInfo(stopId: 'C', stopName: 'Stop C', stopLat: 47.5700, stopLon: -52.7500);

class _FixedSettings extends SettingsNotifier {
  _FixedSettings(this.stopId);
  final String? stopId;
  @override
  AppSettings build() => AppSettings(selectedStopId: stopId);
}

class _FixedPlaces extends SavedPlacesNotifier {
  _FixedPlaces(this.places);
  final List<SavedPlace> places;
  @override
  Future<List<SavedPlace>> build() async => places;
  @override
  Future<void> remove(String id) async => state = AsyncData([for (final p in places) if (p.id != id) p]);
}

class _FixedTrips extends SavedTripsNotifier {
  _FixedTrips(this.trips);
  final List<SavedTrip> trips;
  @override
  Future<List<SavedTrip>> build() async => trips;
}

final _home = SavedPlace(
  id: 'home',
  name: 'Home',
  icon: SavedPlaceIcon.home,
  place: StopPlace(stopId: 'A', name: 'Stop A'),
);

final _toWork = SavedTrip(
  id: 'trip-1',
  name: 'To work',
  from: StopPlace(stopId: 'A', name: 'Stop A'),
  to: StopPlace(stopId: 'E', name: 'Stop E'),
);

ServiceAlert _alertOnRoute1() => ServiceAlert(
      sourceIds: const {'a'},
      header: 'Detour on 1',
      description: 'Use Harbour Drive.',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: const [ServiceAlertTarget(routeId: '1')],
    );

ArrivalRow _arrival(int minutes) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      predictedTime: null,
      minutesAway: minutes,
      liveStatus: null,
      isLive: false,
      tripId: '1-$minutes',
      vehicleNumber: null,
      isEnhanced: false,
      routeRun: '1-1',
    );

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeScreen)));

/// The real home on the test network, at its home sheet.
Future<void> _pumpHome(
  WidgetTester tester, {
  String? stopId = 'C',
  List<SavedPlace> places = const [],
  List<SavedTrip> trips = const [],
  List<ServiceAlert> alerts = const [],
  List<NearbyStop> nearby = const [],
  List<ArrivalRow> arrivals = const [],
  List<Override> overrides = const [],
}) =>
    pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: _now,
      initial: '/',
      alerts: alerts,
      nearby: nearby,
      overrides: [
        settingsProvider.overrideWith(() => _FixedSettings(stopId)),
        savedPlacesProvider.overrideWith(() => _FixedPlaces(places)),
        savedTripsProvider.overrideWith(() => _FixedTrips(trips)),
        for (final t in trips) savedTripNextProvider(t.id).overrideWith((ref) async => const []),
        stopArrivalsProvider.overrideWith((ref, id) async => arrivals),
        ...overrides,
      ],
    );

/// Pulls the sheet from its bar up to half, where saved places, alerts for you and your stop's buses are.
Future<void> _toHalf(WidgetTester tester) async {
  await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
  await tester.pumpAndSettle();
}

/// Pulls the sheet to its full height, where saved trips and nearby stops are.
Future<void> _pullUp(WidgetTester tester) async {
  await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -700));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a quick double tap on Where to? opens one search, and back returns home', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
    // Both taps land before the next frame builds the search page.
    await tester.tap(find.byKey(HomeSheetContent.whereToKey));
    await tester.tap(find.byKey(HomeSheetContent.whereToKey));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen, skipOffstage: false), findsOneWidget, reason: 'one search page, not two');
    GoRouter.of(tester.element(find.byType(SearchScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen, skipOffstage: false), findsNothing);
    // Back home, Where to? opens the search again.
    await tester.tap(find.byKey(HomeSheetContent.whereToKey));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
  });

  group('the one-time tip', () {
    testWidgets('shows once and stays dismissed', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/', homeTipSeen: false);
      expect(find.text(homeTipText), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text(homeTipText), findsNothing);
      expect(await SharedPreferencesAsync().getBool('home_tip_seen.v1'), isTrue);
    });

    testWidgets('tells riders from 1.4 about the two tabs, without naming a button the bar lacks', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/', homeTipSeen: false);
      expect(find.text(homeTipText), findsOneWidget);
      // The bar has no Open board button: the stop line opens the Board (final review I5, WCAG 3.3.2).
      expect(homeTipText, isNot(contains('Open board')));
      // Written for the tabs (final review I3): the Board has not moved onto the map.
      expect(homeTipText, isNot(contains("Everything's on the map")));
      expect(
        homeTipText,
        'Your buses are on the Board tab. Use the Map tab to see the map, plan a trip or follow a bus.',
      );
    });

    testWidgets('a seen tip never shows', (tester) async {
      // pumpPlannerApp's homeTipSeen is the HomeTipSeenNotifier.seen() override.
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/', homeTipSeen: true);
      expect(find.text(homeTipText), findsNothing);
    });

    test('a tip stored as seen stays gone on the next start', () async {
      useInMemoryAlertStore();
      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      expect(await fresh.read(homeTipSeenProvider.future), isFalse);
      await SharedPreferencesAsync().setBool('home_tip_seen.v1', true);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(await c.read(homeTipSeenProvider.future), isTrue);
    });
  });

  testWidgets('at rest the sheet is the slim bar: Where to? and the stop line, whole, the rest one pull up (spec 2026-10-14 §3.1)',
      (tester) async {
    await _pumpHome(
      tester,
      places: [_home],
      alerts: [_alertOnRoute1()],
      arrivals: [_arrival(4), _arrival(12)],
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    var card = tester.getRect(find.byKey(BBSheet.cardKey));
    for (final (name, f) in [
      ('Where to?', find.byKey(HomeSheetContent.whereToKey)),
      ('the stop line', find.byKey(HomeStopLine.lineKey)),
    ]) {
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(card.top), reason: name);
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$name is whole inside the bar');
      expect(r.height, greaterThanOrEqualTo(48), reason: '$name is at least 48 pt tall');
    }
    expect(card.height, lessThan(0.2 * screen.height), reason: 'the bar leaves the map most of the screen');
    for (final (name, f) in [
      ('the saved place', find.text('Home')),
      ('the alert for you', find.textContaining('Detour on 1')),
      ('the next bus', find.byType(ArrivalRowTile).first),
    ]) {
      expect(f.hitTestable(), findsNothing, reason: '$name waits under the bar');
    }

    // Pulled up to half: today's home content (spec §3.3).
    await _toHalf(tester);
    card = tester.getRect(find.byKey(BBSheet.cardKey));
    for (final (name, f) in [
      ('the saved place', find.text('Home')),
      ('the alert for you', find.textContaining('Detour on 1')),
      ('your stop', find.bySemanticsLabel('Your stop, Stop C. Open its buses')),
      ('Open board', find.bySemanticsLabel('Open board, Stop C')),
      ('the next bus', find.byType(ArrivalRowTile).first),
    ]) {
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(card.top), reason: name);
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$name is whole inside the sheet at half');
    }
  });

  testWidgets('the handle is a button: Show more at the bar, Show less pulled up, one stop per tap (spec 2026-10-14 §3.6)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    expect(
      tester.getSemantics(find.byKey(BBSheet.handleKey)),
      isSemantics(label: 'Show more', isButton: true, hasTapAction: true),
    );
    final bar = tester.getRect(find.byKey(BBSheet.cardKey)).height;
    await tester.tap(find.byKey(BBSheet.handleKey));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * homeSheetArea(tester), 1));
    expect(tester.getSemantics(find.byKey(BBSheet.handleKey)), isSemantics(label: 'Show less', isButton: true));
    tester.semantics.tap(find.semantics.byLabel('Show less'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(bar, 1), reason: 'back down to the bar');
    // A card's handle stays the adjustable "Map sheet" control.
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byKey(BBSheet.handleKey)), isSemantics(label: 'Map sheet', isButton: false));
    handle.dispose();
  });

  testWidgets("the handle's target is 44 pt and overlaps the bar's top, yet Where to? keeps its taps (M9)",
      (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    final card = tester.getRect(find.byKey(BBSheet.cardKey));
    final bar = card.height;
    final hit = tester.getRect(find.byKey(BBSheet.handleKey));
    final whereTo = tester.getRect(find.byKey(HomeSheetContent.whereToKey));
    expect(hit.height, greaterThanOrEqualTo(44));
    expect(hit.bottom, greaterThan(whereTo.top), reason: 'it reaches over the top of the bar');
    expect(whereTo.top - card.top, BBSheet.handleButtonExtent, reason: 'the drawn handle keeps its 24 pt');
    // Where to? keeps the taps on it.
    await tester.tapAt(Offset(whereTo.center.dx, whereTo.top + 6));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    GoRouter.of(tester.element(find.byType(SearchScreen))).pop();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(bar, 1));
    // Beside it, in the bar's margin, the same band moves the sheet.
    await tester.tapAt(Offset(card.left + 6, whereTo.top + 6));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, greaterThan(bar + 100), reason: 'up to half');
  });

  testWidgets('an alert that is not on your stop or its routes stays out of the header', (tester) async {
    final elsewhere = ServiceAlert(
      sourceIds: const {'b'},
      header: 'Detour on 9',
      description: '',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: const [ServiceAlertTarget(routeId: '9')],
    );
    await _pumpHome(tester, alerts: [elsewhere]);
    expect(find.textContaining('Detour on 9'), findsNothing);
  });

  testWidgets('a saved place opens trip options to it', (tester) async {
    await _pumpHome(tester, places: [_home]);
    await _toHalf(tester);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    final draft = _c(tester).read(planQueryProvider);
    expect(draft.to, StopPlace(stopId: 'A', name: 'Stop A'));
    expect(draft.from, isNull);
  });

  testWidgets('a saved place starts a fresh trip: an old start, mode and time are dropped (F3, Ruling 14)',
      (tester) async {
    await _pumpHome(tester, places: [_home]);
    await _toHalf(tester);
    _c(tester).read(planQueryProvider.notifier)
      ..setFrom(StopPlace(stopId: 'G', name: 'Stop G'))
      ..setMode(PlanMode.arriveBy)
      ..setTime(_now.add(const Duration(hours: 1)));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    final draft = _c(tester).read(planQueryProvider);
    expect(draft.from, isNull, reason: 'location is off: no start, not the old one');
    expect(draft.to, StopPlace(stopId: 'A', name: 'Stop A'));
    expect(draft.mode, PlanMode.leaveNow);
    expect(draft.time, isNull);
  });

  testWidgets('a saved place starts from My location when the phone knows where it is (F3)', (tester) async {
    await pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: _now,
      initial: '/',
      geolocator: FixedGeolocator(47.57, -52.73),
      overrides: [savedPlacesProvider.overrideWith(() => _FixedPlaces([_home]))],
    );
    await _toHalf(tester);
    _c(tester).read(planQueryProvider.notifier).setFrom(StopPlace(stopId: 'G', name: 'Stop G'));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(planQueryProvider).from, isA<PinPlace>().having((p) => p.label, 'label', myLocationLabel));
  });

  testWidgets('after a saved trip, Where to? plans from no start, leaving now (F3)', (tester) async {
    await _pumpHome(tester, trips: [_toWork]);
    await _pullUp(tester);
    await tester.tap(find.text('To work'));
    await tester.pumpAndSettle();
    _c(tester).read(planQueryProvider.notifier).setMode(PlanMode.arriveBy);
    // Back home, then a new trip.
    _c(tester).read(homeSheetProvider.notifier).home();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeSheetContent.whereToKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'Stop C');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Stop C (C)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    final draft = _c(tester).read(planQueryProvider);
    expect(draft.to, StopPlace(stopId: 'C', name: 'Stop C'));
    expect(draft.from, isNull, reason: 'not the saved trip\'s start');
    expect(draft.mode, PlanMode.leaveNow);
    expect(draft.time, isNull);
  });

  testWidgets("Plan a trip from here starts from that stop, leaving now, and the search's pick keeps it (F3)",
      (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    _c(tester).read(planQueryProvider.notifier)
      ..setTrip(StopPlace(stopId: 'A', name: 'Stop A'), StopPlace(stopId: 'E', name: 'Stop E'))
      ..setMode(PlanMode.arriveBy);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan a trip from here'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'Stop E');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Stop E (E)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    final draft = _c(tester).read(planQueryProvider);
    expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    expect(draft.from, StopPlace(stopId: 'C', name: 'Stop C'));
    expect(draft.to, StopPlace(stopId: 'E', name: 'Stop E'));
    expect(draft.mode, PlanMode.leaveNow);
  });

  testWidgets("changing the options' destination through their title keeps the start (F3)", (tester) async {
    await _pumpHome(tester);
    _c(tester).read(planQueryProvider.notifier)
      ..setTrip(StopPlace(stopId: 'A', name: 'Stop A'), StopPlace(stopId: 'C', name: 'Stop C'))
      ..setMode(PlanMode.arriveBy);
    _c(tester).read(homeSheetProvider.notifier).open(const OptionsSheet());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(OptionsSheetContent.toRowKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'Stop E');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Stop E (E)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    final draft = _c(tester).read(planQueryProvider);
    expect(draft.from, StopPlace(stopId: 'A', name: 'Stop A'));
    expect(draft.to, StopPlace(stopId: 'E', name: 'Stop E'));
    expect(draft.mode, PlanMode.arriveBy);
  });

  testWidgets('a long-press on a saved place offers Remove, and Cancel keeps it', (tester) async {
    await _pumpHome(tester, places: [_home]);
    await _toHalf(tester);
    await tester.longPress(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    await tester.longPress(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
  });

  testWidgets('a saved place offers Remove to a screen reader as a long-press action', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester, places: [_home]);
    final chip = find.bySemanticsLabel('Go to Home');
    expect(tester.getSemantics(chip).getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
    tester.semantics.longPress(find.semantics.byLabel('Go to Home'));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);
    handle.dispose();
  });

  testWidgets('an alert for you is one line, and opens Alerts', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester, alerts: [_alertOnRoute1()]);
    await _toHalf(tester);
    final row = find.bySemanticsLabel('Alert: Detour on 1. Open alerts');
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Service alerts'), findsWidgets);
    handle.dispose();
  });

  testWidgets('the stop line opens your stop on the Board tab (spec 2026-10-15 §2.3)', (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    final c = _c(tester);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    expect(c.read(homeTabProvider), HomeTab.board);
    expect(c.read(boardStopProvider), const BoardStop('C'));
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>(), reason: 'the map is left as it was');
  });

  testWidgets('pulled up, Your stop opens its sheet', (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    await _toHalf(tester);
    await tester.tap(find.bySemanticsLabel('Your stop, Stop C. Open its buses'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
  });

  testWidgets('a saved trip opens its options', (tester) async {
    await _pumpHome(tester, trips: [_toWork]);
    await _pullUp(tester);
    await tester.tap(find.text('To work'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    final draft = _c(tester).read(planQueryProvider);
    expect(draft.from, StopPlace(stopId: 'A', name: 'Stop A'));
    expect(draft.to, StopPlace(stopId: 'E', name: 'Stop E'));
  });

  testWidgets('a nearby stop opens its sheet, and does not become your stop', (tester) async {
    await _pumpHome(tester, stopId: null, nearby: const [NearbyStop(stop: _stopC, distanceMeters: 80)]);
    await _pullUp(tester);
    await tester.tap(find.text('Stop C · 80m'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    expect(_c(tester).read(settingsProvider).selectedStopId, isNull, reason: 'the star on the stop sheet does that');
  });

  testWidgets('a nearby stop opens its sheet at half (F1, spec §3.2)', (tester) async {
    await _pumpHome(tester, stopId: null, nearby: const [NearbyStop(stop: _stopC, distanceMeters: 80)]);
    await _pullUp(tester);
    await tester.tap(find.text('Stop C · 80m'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = homeSheetArea(tester);
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1));
  });

  testWidgets('the home sheet has a tall half; other sheets a half of their own (F1 minor)', (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    expect(tester.widget<BBSheet>(find.byType(BBSheet)).halfFraction, greaterThanOrEqualTo(0.75));
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    final stop = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(stop.halfFraction, closeTo(math.max(0.5, stop.peekFraction + 0.05), 0.0001));
  });

  group('a stop sheet closes (F2, spec §3.2)', () {
    testWidgets('with its Close button', (tester) async {
      await _pumpHome(tester, arrivals: [_arrival(4)]);
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    });

    testWidgets('swiped down past its peek', (tester) async {
      await _pumpHome(tester, arrivals: [_arrival(4)]);
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('STOP C'), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
      expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
    });

    testWidgets('swiped down, it goes back to the sheet under it', (tester) async {
      await _pumpHome(tester, arrivals: [_arrival(4)]);
      final sheets = _c(tester).read(homeSheetProvider.notifier);
      _c(tester).read(planQueryProvider.notifier).setTrip(StopPlace(stopId: 'A', name: 'Stop A'), StopPlace(stopId: 'C', name: 'Stop C'));
      sheets.open(const OptionsSheet());
      sheets.open(const StopSheet('C'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('STOP C'), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    });

    testWidgets('a drag down from half stops at peek first', (tester) async {
      await _pumpHome(tester, arrivals: [_arrival(4)]);
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
      final area = homeSheetArea(tester);
      final half = tester.getRect(find.byKey(BBSheet.cardKey)).height;
      // A short, slow drag: from half to a little above peek, where it snaps to peek and stays open.
      await tester.timedDrag(find.text('STOP C'), Offset(0, half - (sheet.peekFraction + 0.02) * area),
          const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.peekFraction * area, 1));
    });

    testWidgets('collapsed to peek, the same stop opened again (a second notification tap) comes back to half', (
      tester,
    ) async {
      await _pumpHome(tester, arrivals: [_arrival(4)]);
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
      final area = homeSheetArea(tester);
      final half = tester.getRect(find.byKey(BBSheet.cardKey)).height;
      await tester.timedDrag(find.text('STOP C'), Offset(0, half - (sheet.peekFraction + 0.02) * area),
          const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.peekFraction * area, 1));

      // A link to the stop opens it again.
      GoRouter.of(routerElement(tester)).go('/stop/C');
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
      expect(_c(tester).read(homeSheetProvider.notifier).stack, hasLength(2), reason: 'still one card over home');
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(half, 1));
    });

    testWidgets('the home sheet itself never swipes away', (tester) async {
      await _pumpHome(tester, arrivals: [_arrival(4)]);
      expect(tester.widget<BBSheet>(find.byType(BBSheet)).dismissible, isFalse);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
    });
  });

  testWidgets('no stop and no location: "Choose your stop" opens a stop search with a stop-number hint (F5, §4.4)',
      (tester) async {
    await _pumpHome(tester, stopId: null);
    await tester.tap(find.text('Choose your stop'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Type the stop number on the pole'), findsOneWidget);
    expect(find.text('Choose on map'), findsNothing, reason: 'this search is for a stop, not a place to go');
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'Stop C');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Stop C (C)'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    expect(_c(tester).read(settingsProvider).selectedStopId, 'C', reason: 'the chosen stop becomes your stop');
  });

  testWidgets('no stop chosen: "Choose your stop" pulls the sheet up to the nearby stops', (tester) async {
    await _pumpHome(tester, stopId: null, nearby: const [NearbyStop(stop: _stopC, distanceMeters: 80)]);
    expect(find.text('Choose your stop'), findsOneWidget);
    final before = tester.getRect(find.byKey(BBSheet.cardKey)).top;
    await tester.tap(find.text('Choose your stop'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, lessThan(before));
    expect(find.text('Stop C · 80m'), findsOneWidget);
  });

  group('the nearby list', () {
    const mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);

    GtfsRepository repoWithRoutes(List<String> names) {
      final repo = GtfsRepository();
      repo.stopsById['1150'] = mun;
      final times = <StopTimeRow>[];
      for (var i = 0; i < names.length; i++) {
        repo.routesById['r$i'] = RouteInfo(routeId: 'r$i', routeShortName: names[i], routeLongName: '');
        repo.tripsById['t$i'] =
            TripInfo(tripId: 't$i', routeId: 'r$i', serviceId: 's', tripHeadsign: '', directionId: 0);
        times.add(StopTimeRow(
            tripId: 't$i', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1));
      }
      repo.stopTimesByStopId['1150'] = times;
      return repo;
    }

    /// MUN Centre served by route 10 both ways, route 1 one way and route 24, whose only trip ends here.
    GtfsRepository repoWithDirections() {
      final repo = GtfsRepository();
      repo.stopsById['1150'] = mun;
      for (final r in ['1', '10', '24']) {
        repo.routesById['r$r'] = RouteInfo(routeId: 'r$r', routeShortName: r, routeLongName: '');
      }
      final trips = [
        ('a', 'r10', 'AVALON MALL - MUN CENTRE - DOWNTOWN'),
        ('b', 'r10', 'AVALON MALL - MUN CENTRE - DOWNTOWN'),
        ('c', 'r10', 'MUN CENTRE - AVALON MALL - KELSEY DRIVE'),
        ('d', 'r1', 'MUN-CNA-MI'),
      ];
      for (final (trip, route, headsign) in trips) {
        repo.tripsById[trip] =
            TripInfo(tripId: trip, routeId: route, serviceId: 's', tripHeadsign: headsign, directionId: 0);
        repo.stopTimesByStopId.putIfAbsent('1150', () => []).add(StopTimeRow(
            tripId: trip, arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1));
        repo.stopTimesByStopId.putIfAbsent('9000', () => []).add(StopTimeRow(
            tripId: trip, arrivalTime: '08:10:00', departureTime: '08:10:00', stopId: '9000', stopSequence: 2));
      }
      repo.tripsById['e'] =
          const TripInfo(tripId: 'e', routeId: 'r24', serviceId: 's', tripHeadsign: 'MUN EXPRESS', directionId: 0);
      repo.stopTimesByStopId['1150']!.add(const StopTimeRow(
          tripId: 'e', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 5));
      return repo;
    }

    Future<void> pumpList(
      WidgetTester tester, {
      required GtfsRepository Function() repo,
      FutureOr<List<NearbyStop>> Function()? nearby,
      double textScale = 1.0,
    }) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          gtfsRepositoryProvider.overrideWith((ref) => repo()),
          nearestStopsProvider.overrideWith((ref) async => nearby == null ? const <NearbyStop>[] : await nearby()),
        ],
        child: MaterialApp(
          theme: BBTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: SingleChildScrollView(child: NearMeList())),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a pill for every route serving the stop', (tester) async {
      final names = ['1', '2', '3', '6', '9', '10', '10A', '11', '12'];
      await pumpList(tester,
          repo: () => repoWithRoutes(names), nearby: () => const [NearbyStop(stop: mun, distanceMeters: 80)]);
      expect(find.byType(RouteBadge), findsNWidgets(9));
      expect(find.text('10A'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('rows have the stop, its number and distance, and a spoken label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester,
          repo: () => repoWithRoutes(['10']), nearby: () => const [NearbyStop(stop: mun, distanceMeters: 80)]);
      expect(find.text('MUN Centre'), findsOneWidget);
      expect(find.text('Stop 1150 · 80m'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('MUN Centre, stop 1150, 80m away, routes 10')), findsOneWidget);
      expect(find.byType(RouteBadge), findsOneWidget);
      handle.dispose();
    });

    testWidgets('shows where each route goes from the stop', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester,
          repo: repoWithDirections, nearby: () => const [NearbyStop(stop: mun, distanceMeters: 80)]);
      expect(find.byType(RouteBadge), findsNWidgets(3));
      expect(find.text('Downtown · Kelsey Drive'), findsOneWidget);
      expect(find.text('MI'), findsOneWidget);
      // Route 24 only ends here: chip, no destination.
      expect(find.text('24'), findsOneWidget);
      expect(
        find.bySemanticsLabel('MUN Centre, stop 1150, 80m away, routes 1 to MI, 10 to Downtown or Kelsey Drive, 24'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('long destinations fit a 320pt phone at text scale 2.0', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpList(tester,
          repo: repoWithDirections, nearby: () => const [NearbyStop(stop: mun, distanceMeters: 80)], textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.text('Downtown · Kelsey Drive'), findsOneWidget);
    });

    testWidgets('empty and error states', (tester) async {
      await pumpList(tester, repo: () => repoWithRoutes(['10']), nearby: () => const []);
      expect(find.text('No stops found within 800m.'), findsOneWidget);
      await pumpList(tester,
          repo: () => repoWithRoutes(['10']), nearby: () => Future<List<NearbyStop>>.error(Exception('gps off')));
      // Riverpod retries a failed provider with backoff before surfacing the error.
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('Unable to get location'), findsOneWidget);
      expect(find.text('Please enable location services and grant permission.'), findsOneWidget);
    });
  });
}

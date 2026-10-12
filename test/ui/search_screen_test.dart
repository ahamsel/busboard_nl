import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_pick_provider.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

final _now = DateTime(2026, 10, 12, 13, 0);

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.5720, stopLon: -52.7480);

/// The test network with a stop numbered 1150 added, as Metrobus numbers its stops.
TestNetwork _network() {
  final net = TestNetwork();
  net.repo.stopsById[_mun.stopId] = _mun;
  return net;
}

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(routerElement(t));

/// The real home, then [location] pushed on top of it, as the sheet's buttons do.
Future<void> _openSearch(WidgetTester tester, {String location = '/search', GeolocatorPlatform? geolocator}) async {
  await pumpPlannerApp(tester, net: _network(), now: _now, initial: '/', geolocator: geolocator);
  unawaited(GoRouter.of(routerElement(tester)).push(location));
  await tester.pumpAndSettle();
}

/// Types stop 1150 into the search field and taps its row.
Future<void> _findMun(WidgetTester tester) async {
  await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('MUN Centre').first);
  await tester.pumpAndSettle();
}

/// A phone whose location fix is held until the test completes [fix].
class _HeldGeolocator extends FixedGeolocator {
  _HeldGeolocator() : super(47.57, -52.73);
  final fix = Completer<void>();

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    await fix.future;
    return super.getCurrentPosition(locationSettings: locationSettings);
  }
}

/// Recent places whose saving is held until the test completes [saved].
class _HeldRecentStore extends RecentPlaceStore {
  final saved = Completer<void>();

  @override
  Future<void> push(Place p) async {
    await saved.future;
    return super.push(p);
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a stop number lists that stop first; Go here opens options to it', (tester) async {
    await pumpPlannerApp(tester, net: _network(), now: _now, initial: '/');
    await tester.tap(find.byKey(HomeSheetContent.whereToKey));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('MUN Centre').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    expect(find.byType(SearchScreen), findsNothing);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(c.read(planQueryProvider).to, StopPlace(stopId: '1150', name: 'MUN Centre'));
    expect(c.read(recentPlacesProvider).value!.first, StopPlace(stopId: '1150', name: 'MUN Centre'));
  });

  testWidgets('a stop id typed in full comes before stops that only mention it', (tester) async {
    final net = _network();
    net.repo.stopsById['1000'] = const StopInfo(
      stopId: '1000',
      stopName: 'Near 1150 Corner',
      stopLat: 47.5,
      stopLon: -52.7,
    );
    await pumpPlannerApp(tester, net: net, now: _now, initial: '/');
    unawaited(GoRouter.of(routerElement(tester)).push('/search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
    await tester.pumpAndSettle();
    final mun = tester.getTopLeft(find.textContaining('MUN Centre')).dy;
    final corner = tester.getTopLeft(find.textContaining('Near 1150 Corner')).dy;
    expect(mun, lessThan(corner));
  });

  testWidgets('See its buses opens the stop sheet', (tester) async {
    await _openSearch(tester);
    await _findMun(tester);
    await tester.tap(find.text('See its buses'));
    await tester.pumpAndSettle();
    final c = _c(tester);
    expect(find.byType(SearchScreen), findsNothing);
    expect(c.read(homeSheetProvider), const StopSheet('1150'));
    expect(c.read(planQueryProvider).to, isNull);
  });

  testWidgets('no location: the destination is set and the start stays empty', (tester) async {
    await _openSearch(tester);
    await _findMun(tester);
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    final c = _c(tester);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(c.read(planQueryProvider).to, StopPlace(stopId: '1150', name: 'MUN Centre'));
    expect(c.read(planQueryProvider).from, isNull);
  });

  testWidgets('with location: the start becomes My location', (tester) async {
    await _openSearch(tester, geolocator: FixedGeolocator(47.57, -52.73));
    await _findMun(tester);
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    final c = _c(tester);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(c.read(planQueryProvider).from, isA<PinPlace>().having((p) => p.label, 'label', myLocationLabel));
  });

  testWidgets('with keep=1 (the options\' title, Plan a trip from here) a start already chosen is kept', (tester) async {
    await _openSearch(tester, location: '/search?keep=1', geolocator: FixedGeolocator(47.57, -52.73));
    final start = StopPlace(stopId: 'A', name: 'Stop A');
    _c(tester).read(planQueryProvider.notifier).setFrom(start);
    await _findMun(tester);
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(planQueryProvider).from, start);
  });

  testWidgets('a plain search (Where to?) starts a fresh trip from My location (F3, Ruling 14)', (tester) async {
    await _openSearch(tester, geolocator: FixedGeolocator(47.57, -52.73));
    _c(tester).read(planQueryProvider.notifier)
      ..setFrom(StopPlace(stopId: 'A', name: 'Stop A'))
      ..setMode(PlanMode.arriveBy)
      ..setTime(_now.add(const Duration(hours: 2)));
    await _findMun(tester);
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    final draft = _c(tester).read(planQueryProvider);
    expect(draft.from, isA<PinPlace>().having((p) => p.label, 'label', myLocationLabel));
    expect(draft.mode, PlanMode.leaveNow);
    expect(draft.time, isNull);
  });

  testWidgets('empty query shows Choose on map, saved places and recent; end=from adds My location', (tester) async {
    await _openSearch(tester);
    final c = _c(tester);
    await c
        .read(savedPlacesProvider.notifier)
        .put(
          SavedPlace(
            id: 'w',
            name: 'Work',
            icon: SavedPlaceIcon.work,
            place: StopPlace(stopId: 'E', name: 'Stop E'),
          ),
        );
    await c.read(recentPlacesProvider.notifier).push(StopPlace(stopId: 'C', name: 'Stop C'));
    await tester.pumpAndSettle();
    expect(find.text('Search for a stop or a place'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Choose on map'), findsOneWidget);
    expect(find.text(myLocationLabel), findsNothing);
    expect(find.text('Saved places'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Stop C'), findsOneWidget);

    GoRouter.of(routerElement(tester)).pop();
    await tester.pumpAndSettle();
    unawaited(GoRouter.of(routerElement(tester)).push('/search?end=from'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a start'), findsOneWidget);
    expect(find.text('Choose on map'), findsOneWidget);
    expect(find.text(myLocationLabel), findsOneWidget);
  });

  testWidgets('a query also finds saved places by name, in any case', (tester) async {
    await _openSearch(tester);
    await _c(tester)
        .read(savedPlacesProvider.notifier)
        .put(
          SavedPlace(
            id: 'w',
            name: 'Work',
            icon: SavedPlaceIcon.work,
            place: StopPlace(stopId: 'E', name: 'Stop E'),
          ),
        );
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'wOR');
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    final c = _c(tester);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(c.read(planQueryProvider).to, StopPlace(stopId: 'E', name: 'Stop E'));
  });

  testWidgets('end=from: picking a stop sets the start and returns', (tester) async {
    await _openSearch(tester, location: '/search?end=from');
    await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('MUN Centre').first);
    await tester.pumpAndSettle();
    final c = _c(tester);
    expect(find.byType(SearchScreen), findsNothing);
    expect(c.read(planQueryProvider).from, StopPlace(stopId: '1150', name: 'MUN Centre'));
    expect(c.read(planQueryProvider).to, isNull);
    expect(c.read(homeSheetProvider), const HomeSheetHome());
  });

  testWidgets('end=from: My location sets the start from a fix', (tester) async {
    await _openSearch(tester, location: '/search?end=from', geolocator: FixedGeolocator(47.57, -52.73));
    await tester.tap(find.text(myLocationLabel));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(_c(tester).read(planQueryProvider).from, isA<PinPlace>().having((p) => p.label, 'label', myLocationLabel));
  });

  testWidgets('end=from: My location with no fix says so and stays', (tester) async {
    await _openSearch(tester, location: '/search?end=from');
    await tester.tap(find.text(myLocationLabel));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text("Couldn't find your location"), findsOneWidget);
    expect(_c(tester).read(planQueryProvider).from, isNull);
  });

  testWidgets('save=1 saves a named place as Home', (tester) async {
    await _openSearch(tester, location: '/search?save=1');
    expect(find.text('Save a place'), findsOneWidget);
    expect(find.text('Choose on map'), findsNothing);
    await _findMun(tester);
    final nameField = find.byWidgetPredicate((w) => w is BBTextField && w.hint == 'Name');
    expect(
      tester.widget<EditableText>(find.descendant(of: nameField, matching: find.byType(EditableText))).controller.text,
      'MUN Centre',
    );
    await tester.enterText(nameField, 'My place');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final c = _c(tester);
    expect(find.byType(SearchScreen), findsNothing);
    final saved = c.read(savedPlacesProvider).value!.single;
    expect(saved.icon, SavedPlaceIcon.home);
    expect(saved.name, 'My place');
    expect(saved.place, StopPlace(stopId: '1150', name: 'MUN Centre'));
    expect(c.read(planQueryProvider).to, isNull);
    expect(c.read(homeSheetProvider), const HomeSheetHome());
  });

  testWidgets('save=1: a blank name keeps the place name; Cancel saves nothing', (tester) async {
    await _openSearch(tester, location: '/search?save=1');
    await _findMun(tester);
    final nameField = find.byWidgetPredicate((w) => w is BBTextField && w.hint == 'Name');
    await tester.enterText(nameField, '   ');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(_c(tester).read(savedPlacesProvider).value, isEmpty);

    await tester.tap(find.textContaining('MUN Centre').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byWidgetPredicate((w) => w is BBTextField && w.hint == 'Name'), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = _c(tester).read(savedPlacesProvider).value!.single;
    expect(saved.name, 'MUN Centre');
    expect(saved.icon, SavedPlaceIcon.star);
  });

  testWidgets('Choose on map arms the map pick and returns home', (tester) async {
    await _openSearch(tester);
    await tester.tap(find.text('Choose on map'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(mapPickProvider), MapPick.to);
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('end=from: Choose on map arms the map pick for the start', (tester) async {
    await _openSearch(tester, location: '/search?end=from');
    await tester.tap(find.text('Choose on map'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(mapPickProvider), MapPick.from);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the stop sheet\'s Plan a trip from here starts the search from that stop', (tester) async {
    await pumpPlannerApp(tester, net: _network(), now: _now, initial: '/board/C');
    // The sheet's header holds the button; bring the sheet up so it is on screen.
    await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StopSheetContent.planFromKey));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    final c = _c(tester);
    expect(c.read(planQueryProvider).from, StopPlace(stopId: 'C', name: 'Stop C'));
    expect(c.read(planQueryProvider).to, isNull);
  });

  testWidgets('leaving while the fix is awaited still sets the destination, the start and the options', (tester) async {
    final geo = _HeldGeolocator();
    await _openSearch(tester, geolocator: geo);
    await _findMun(tester);
    await tester.tap(find.text('Go here'));
    await tester.pump();
    final c = _c(tester);
    expect(c.read(planQueryProvider).to, StopPlace(stopId: '1150', name: 'MUN Centre'));
    expect(c.read(planQueryProvider).from, isNull);

    GoRouter.of(routerElement(tester)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    geo.fix.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(c.read(planQueryProvider).from, isA<PinPlace>().having((p) => p.label, 'label', myLocationLabel));
    expect(c.read(planQueryProvider).to, StopPlace(stopId: '1150', name: 'MUN Centre'));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('leaving while the recent place is saved still sets the destination, the start and the options', (
    tester,
  ) async {
    late final _HeldRecentStore store;
    await pumpPlannerApp(
      tester,
      net: _network(),
      now: _now,
      initial: '/',
      geolocator: FixedGeolocator(47.57, -52.73),
      overrides: [recentPlaceStoreProvider.overrideWith((ref) => store = _HeldRecentStore())],
    );
    unawaited(GoRouter.of(routerElement(tester)).push('/search'));
    await tester.pumpAndSettle();
    await _findMun(tester);
    await tester.tap(find.text('Go here'));
    await tester.pump();

    GoRouter.of(routerElement(tester)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    store.saved.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final c = _c(tester);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(c.read(planQueryProvider).to, StopPlace(stopId: '1150', name: 'MUN Centre'));
    expect(c.read(planQueryProvider).from, isA<PinPlace>().having((p) => p.label, 'label', myLocationLabel));
  });

  testWidgets('while the fix is awaited the screen says so and a second tap does nothing', (tester) async {
    final geo = _HeldGeolocator();
    await _openSearch(tester, geolocator: geo);
    final c = _c(tester);
    await _findMun(tester);
    var changes = 0;
    c.listen(planQueryProvider, (_, _) => changes++);
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    expect(find.text('Finding you…'), findsOneWidget);

    await tester.tap(find.textContaining('MUN Centre').first);
    await tester.pumpAndSettle();
    expect(find.text('Go here'), findsNothing);

    geo.fix.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(c.read(recentPlacesProvider).value, hasLength(1));
    // The destination, then the start: once each.
    expect(changes, 2);
    expect(find.byType(SearchScreen), findsNothing);
  });

  testWidgets('Back on a search that is the first page goes home', (tester) async {
    await pumpPlannerApp(tester, net: _network(), now: _now, initial: '/search');
    expect(find.byType(SearchScreen), findsOneWidget);
    await tester.tap(find.byIcon(BBIcons.back));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('save=1: a query lists stops but not saved places', (tester) async {
    await _openSearch(tester, location: '/search?save=1');
    await _c(tester)
        .read(savedPlacesProvider.notifier)
        .put(
          SavedPlace(
            id: 'w',
            name: 'Work',
            icon: SavedPlaceIcon.work,
            place: StopPlace(stopId: 'E', name: 'Stop E'),
          ),
        );
    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'work');
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsNothing);
    expect(find.text('No stops match "work"'), findsOneWidget);
  });
}

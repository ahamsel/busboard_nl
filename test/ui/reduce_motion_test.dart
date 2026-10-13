import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/options_sheet.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../helpers/planner_app.dart';
import '../map/support/fake_map_surface.dart';
import '../trip_planner/test_network.dart';

class _StopASettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'A');
}

ArrivalRow _live(int minutes, String trip) => ArrivalRow(
      routeShortName: '10',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('08:30:00'),
      predictedTime: GtfsTime.parse('08:31:00'),
      minutesAway: minutes,
      isLive: true,
      liveStatus: LiveStatus.behind,
      tripId: trip,
      vehicleNumber: '2134',
    );

/// One frame for [what], then frames 16 ms apart: with Reduce Motion, nothing may still be asking for frames
/// 100 ms later (spec §8). Any real animation (120 ms or more) would. (Not `hasRunningAnimations`: a
/// LayoutBuilder rebuild also registers a frame callback, and the 1 ms Reduce Motion detent move ends a
/// frame after it starts.)
Future<void> settlesWithin100ms(WidgetTester tester, String what) async {
  await tester.pump();
  var elapsed = Duration.zero;
  while (tester.binding.hasScheduledFrame && elapsed < const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 16));
    elapsed += const Duration(milliseconds: 16);
  }
  expect(tester.binding.hasScheduledFrame, isFalse,
      reason: '$what: still asking for frames ${elapsed.inMilliseconds} ms later');
}

void main() {
  testWidgets('with Reduce Motion, home, a stop sheet and options settle within 100 ms of each interaction',
      (tester) async {
    await pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: DateTime(testDay.year, testDay.month, testDay.day, 8, 1),
      reduceMotion: true,
      overrides: [
        settingsProvider.overrideWith(_StopASettings.new),
        stopArrivalsProvider.overrideWith((ref, id) async => [_live(0, 'a'), _live(6, 'b'), _live(12, 'c')]),
      ],
    );
    await settlesWithin100ms(tester, 'home at rest');

    // A stop sheet, from Your stop.
    await tester.tap(find.bySemanticsLabel(RegExp('^Your stop')));
    await settlesWithin100ms(tester, 'opening the stop sheet');
    expect(find.byType(BBLiveDot), findsWidgets, reason: 'the live dot is there, but still');
    await tester.tap(find.byKey(StopSheetContent.refreshKey));
    await settlesWithin100ms(tester, 'refreshing the stop');
    await tester.tap(find.byKey(StopSheetContent.closeKey));
    await settlesWithin100ms(tester, 'closing the stop sheet');

    // Options.
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    c.read(planQueryProvider.notifier).setTrip(
          StopPlace(stopId: 'A', name: 'Stop A'),
          StopPlace(stopId: 'C', name: 'Stop C'),
        );
    c.read(homeSheetProvider.notifier).open(const OptionsSheet());
    await settlesWithin100ms(tester, 'opening options');
    await tester.tap(find.text('Leave by'));
    await settlesWithin100ms(tester, 'choosing Leave by');

    // The picker: opening, a quick pick turning the wheels, closing.
    await tester.tap(find.byKey(OptionsSheetContent.whenButtonKey));
    await settlesWithin100ms(tester, 'opening the picker');
    await tester.ensureVisible(find.text('In 30 min'));
    await tester.pump();
    await tester.tap(find.text('In 30 min'));
    await settlesWithin100ms(tester, 'a quick pick turning the wheels');
    await tester.tap(find.byKey(BBWhenPicker.closeKey));
    await settlesWithin100ms(tester, 'closing the picker');
  });

  testWidgets('with Reduce Motion, My location centres the map but the ping draws nothing and no frames linger',
      (tester) async {
    final surface = FakeMapSurface()..location = const LatLng(47.55, -52.70);
    Widget map(MapViewConfig config) {
      scheduleMicrotask(() => config.onReady(surface, surface));
      return const ColoredBox(key: ValueKey('stub-map'), color: Color(0xFFEEF1F4));
    }

    await pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: DateTime(testDay.year, testDay.month, testDay.day, 8, 1),
      reduceMotion: true,
      geolocator: FixedGeolocator(47.55, -52.70),
      mapView: map,
    );
    await settlesWithin100ms(tester, 'home at rest');
    expect(find.byType(BBPing), findsNothing);

    await tester.tap(find.bySemanticsLabel('My location'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(surface.moves, hasLength(1), reason: 'the tap went through: the camera moved to the rider');
    expect(find.byType(BBPing), findsOneWidget, reason: 'the ping was asked for (not skipped), so this is not vacuous');
    expect(find.byKey(BBPing.ringKey), findsNothing, reason: 'Reduce Motion: no rings are drawn');
    await settlesWithin100ms(tester, 'the location ping');
  });
}

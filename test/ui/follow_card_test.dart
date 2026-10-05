import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/follow_card.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

TripStop _stop(String id, String name, int seq, int seconds) =>
    TripStop(stopId: id, name: name, sequence: seq, progress: seq / 10, departureSeconds: seconds);

final _stops = [
  _stop('a', 'Stop A', 1, 43200),
  _stop('b', 'Stop B', 2, 43260),
  _stop('1150', 'MUN Centre', 3, 43320),
  _stop('c', 'Stop C', 4, 43380),
];

BusTrackingState _bus({bool stale = false, int? schedDiff = -1, String headsign = 'Downtown'}) => BusTrackingState(
      routeRun: 'Rt 10',
      vehicleId: '2573',
      routeNumber: 10,
      headsign: headsign,
      lat: 47.56,
      lon: -52.71,
      heading: 90,
      speedKmh: 29,
      lastGpsTime: DateTime.now().subtract(const Duration(seconds: 12)),
      status: stale ? BusStatus.stale : BusStatus.active,
      lastUpdateTime: DateTime.now(),
      schedDiffMins: schedDiff,
    );

FollowSnapshot _snap({
  int busIndex = 0,
  int? yourIndex = 2,
  int? toGo = 2,
  bool arrived = false,
  bool stale = false,
  bool found = true,
  int? schedDiff = -1,
  String busHeadsign = 'Downtown',
  List<TripStop>? stops,
}) =>
    FollowSnapshot(
      vehicleId: '2573',
      bus: found ? _bus(stale: stale, schedDiff: schedDiff, headsign: busHeadsign) : null,
      tripId: 't1',
      stale: stale,
      lastSeenAgo: stale ? const Duration(seconds: 75) : const Duration(seconds: 10),
      stops: stops ?? _stops,
      busIndex: busIndex,
      yourStopIndex: yourIndex,
      stopsToYourStop: toGo,
      arrived: arrived,
      ended: null,
    );

Future<void> _host(
  WidgetTester tester,
  FollowSnapshot snapshot, {
  int? minutes = 4,
  String? tripHeadsign = 'Downtown',
  VoidCallback? onStop,
  VoidCallback? onSeeAll,
  double textScale = 1,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: BBTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: FollowCardHeader(
            snapshot: snapshot,
            yourStopName: 'MUN Centre',
            minutesToYourStop: minutes,
            tripHeadsign: tripHeadsign,
            onStop: onStop ?? () {},
            onSeeAll: onSeeAll ?? () {},
          ),
        ),
        SliverToBoxAdapter(child: FollowCardBody(snapshot: snapshot)),
      ],
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('stops-to-go wording', () {
    expect(stopsToGoText(2, 'MUN Centre'), '2 stops to MUN Centre');
    expect(stopsToGoText(1, 'MUN Centre'), '1 stop to MUN Centre');
    expect(stopsToGoText(0, 'MUN Centre'), 'Next stop: MUN Centre');
    expect(stopsToGoText(null, 'MUN Centre'), "Your stop isn't on this trip");
  });

  test('ETA is the timetable shifted by the delay, or marked sched', () {
    final stop = _stop('x', 'X', 1, 43320); // 12:02
    expect(etaText(stop, -1), '12:03', reason: '1 min late');
    expect(etaText(stop, 2), '12:00', reason: '2 min early');
    expect(etaText(stop, null), '12:02 sched');
    expect(etaText(TripStop(stopId: 'y', name: 'Y', sequence: 1, progress: null, departureSeconds: null), 0), '');
  });

  testWidgets('header: destination, bus and lateness, stops to go, minutes', (tester) async {
    final semantics = tester.ensureSemantics();
    await _host(tester, _snap());
    expect(find.bySemanticsLabel('Route 10'), findsOneWidget);
    expect(find.text('to Downtown'), findsOneWidget);
    expect(find.text('Bus 2573 · 1 min late'), findsOneWidget);
    expect(find.text('2 stops to MUN Centre'), findsOneWidget);
    expect(find.text('4 min'), findsOneWidget);
    expect(tester.getSemantics(find.text('2 stops to MUN Centre')), matchesSemantics(
      label: '2 stops to MUN Centre',
      isLiveRegion: true,
    ));
    semantics.dispose();
  });

  testWidgets('header: minutes read Now at zero', (tester) async {
    await _host(tester, _snap(), minutes: 0);
    expect(find.text('Now'), findsOneWidget);
  });

  testWidgets('header: stale bus says when it was last seen', (tester) async {
    await _host(tester, _snap(stale: true));
    expect(find.text('Bus 2573 · Last seen 1 min ago'), findsOneWidget);
  });

  testWidgets('header: a bus not in the feed yet is being found', (tester) async {
    await _host(tester, _snap(found: false));
    expect(find.text('Finding bus 2573…'), findsOneWidget);
    expect(find.text('Stop following'), findsOneWidget);
  });

  testWidgets('header: arrival says so', (tester) async {
    await _host(tester, _snap(busIndex: 2, toGo: 0, arrived: true));
    expect(find.text('Arrived at MUN Centre'), findsOneWidget);
  });

  testWidgets('header: during the arrival linger the followed trip, not the bus next trip, is described', (tester) async {
    // After arrival the bus can already be on its next trip, with another
    // headsign and delay; the card must keep describing the followed trip.
    await _host(tester, _snap(busIndex: 2, toGo: 0, arrived: true, busHeadsign: 'Airport', schedDiff: -9));
    expect(find.text('to Downtown'), findsOneWidget);
    expect(find.text('to Airport'), findsNothing);
    expect(find.text('Bus 2573'), findsOneWidget);
    expect(find.textContaining('late'), findsNothing);
  });

  testWidgets('header: before arrival the live headsign wins, the trip headsign fills a gap', (tester) async {
    await _host(tester, _snap(busHeadsign: 'Airport'));
    expect(find.text('to Airport'), findsOneWidget);
    await _host(tester, _snap(busHeadsign: ''));
    expect(find.text('to Downtown'), findsOneWidget);
  });

  testWidgets('header: your stop not on the trip says so', (tester) async {
    await _host(tester, _snap(yourIndex: null, toGo: null), minutes: null);
    expect(find.text("Your stop isn't on this trip"), findsOneWidget);
  });

  testWidgets('both buttons call back', (tester) async {
    var stopped = 0, seeAll = 0;
    await _host(tester, _snap(), onStop: () => stopped++, onSeeAll: () => seeAll++);
    await tester.tap(find.text('Stop following'));
    await tester.tap(find.text('See all stops'));
    expect((stopped, seeAll), (1, 1));
  });

  testWidgets('body: stops after the bus with ETAs, your stop emphasised', (tester) async {
    await _host(tester, _snap());
    expect(find.text('Stop A'), findsNothing, reason: 'already driven');
    expect(find.text('Stop B'), findsOneWidget);
    expect(find.text('Stop C'), findsOneWidget);
    expect(find.text('12:02'), findsOneWidget, reason: 'B at 12:01 and 1 min late');
    expect(find.text('12:03'), findsOneWidget);
    expect(find.text('12:04'), findsOneWidget);
    // "MUN Centre" also appears in the header line; the row is the one with
    // the "Your stop" label.
    expect(find.text('Your stop'), findsOneWidget);
    expect(find.text('MUN Centre'), findsOneWidget);
  });

  testWidgets('body: an unknown delay marks ETAs as scheduled', (tester) async {
    await _host(tester, _snap(schedDiff: null));
    expect(find.text('12:01 sched'), findsOneWidget);
  });

  testWidgets("body: next six stops when your stop isn't on the trip", (tester) async {
    final ten = [for (var i = 0; i < 10; i++) _stop('s$i', 'Stop $i', i + 1, 43200 + i * 60)];
    await _host(tester, _snap(stops: ten, busIndex: 2, yourIndex: null, toGo: null), minutes: null);
    for (var i = 3; i <= 8; i++) {
      expect(find.text('Stop $i'), findsOneWidget, reason: 'Stop $i is among the next six');
    }
    expect(find.text('Stop 2'), findsNothing);
    expect(find.text('Stop 9'), findsNothing);
    expect(find.text('Your stop'), findsNothing);
  });

  testWidgets('out-of-range indices (a shape change) never throw', (tester) async {
    for (final (bus, yours) in [(9, 12), (-5, -1), (3, 7), (1, 9), (-1, null)]) {
      await _host(tester, _snap(busIndex: bus, yourIndex: yours, toGo: 2));
      expect(tester.takeException(), isNull, reason: 'busIndex $bus, yourStopIndex $yours');
    }
    await _host(tester, _snap(stops: const [], busIndex: 3, yourIndex: 2));
    expect(tester.takeException(), isNull, reason: 'no stops at all');
  });

  testWidgets('the strip survives 2x text at the smallest width', (tester) async {
    await _host(tester, _snap(), textScale: 2, width: 320);
    expect(tester.takeException(), isNull);
  });
}

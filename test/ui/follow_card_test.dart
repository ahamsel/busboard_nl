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
  String? routeLabel,
  String? yourStopName = 'MUN Centre',
  double textScale = 1,
  double width = 390,
  bool use24h = true,
}) async {
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: BBTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), alwaysUse24HourFormat: use24h),
      child: child!,
    ),
    home: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: FollowCardHeader(
            snapshot: snapshot,
            yourStopName: yourStopName,
            minutesToYourStop: minutes,
            tripHeadsign: tripHeadsign,
            routeLabel: routeLabel,
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
    expect(etaText(stop, -1, use24h: true), '12:03', reason: '1 min late');
    expect(etaText(stop, 2, use24h: true), '12:00', reason: '2 min early');
    expect(etaText(stop, null, use24h: true), '12:02 sched');
    expect(etaText(TripStop(stopId: 'y', name: 'Y', sequence: 1, progress: null, departureSeconds: null), 0, use24h: true), '');
    // The device's 12-hour setting, as everywhere else in the app.
    expect(etaText(stop, -1, use24h: false), '12:03 PM');
    expect(etaText(_stop('z', 'Z', 1, 9 * 3600 + 5 * 60), null, use24h: false), '9:05 AM sched');
  });

  testWidgets("body ETAs follow the device's 12-hour setting", (tester) async {
    await _host(tester, _snap(schedDiff: null), use24h: false);
    expect(find.text('12:01 PM sched'), findsOneWidget);
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

  testWidgets('header: arrival names the stop arrived at, even if your stop has changed since', (tester) async {
    await _host(tester, _snap(busIndex: 2, toGo: 0, arrived: true), yourStopName: 'Village Mall');
    expect(find.text('Arrived at MUN Centre'), findsOneWidget);
    expect(find.textContaining('Village Mall'), findsNothing);
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

  /// The strip's markers left to right: 'bus', 'star', or the stop index.
  List<String> stripOrder(WidgetTester tester) {
    final found = find
        .byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('strip-'))
        .evaluate()
        .map((e) => e.widget)
        .toList()
      ..sort((a, b) => tester.getTopLeft(find.byWidget(a)).dx.compareTo(tester.getTopLeft(find.byWidget(b)).dx));
    return [for (final w in found) (w.key! as ValueKey<String>).value.substring('strip-'.length)];
  }

  List<TripStop> thirty() => [for (var i = 0; i < 30; i++) _stop('s$i', 'Stop $i', i + 1, 43200 + i * 60)];

  testWidgets('strip: ends at your stop, never past it', (tester) async {
    // Bus before the first stop, your stop third.
    await _host(tester, _snap(stops: thirty(), busIndex: -1, yourIndex: 2, toGo: 3));
    expect(stripOrder(tester), ['bus', 'dot-0', 'dot-1', 'star']);

    // Bus mid-trip, your stop within reach.
    await _host(tester, _snap(stops: thirty(), busIndex: 4, yourIndex: 7, toGo: 3));
    expect(stripOrder(tester), ['dot-4', 'bus', 'dot-5', 'dot-6', 'star']);
  });

  testWidgets('strip: a far stop of yours replaces the last dot, at most 7 markers', (tester) async {
    await _host(tester, _snap(stops: thirty(), busIndex: 3, yourIndex: 25, toGo: 22));
    final order = stripOrder(tester);
    expect(order.where((m) => m != 'bus').length, lessThanOrEqualTo(7));
    expect(order.last, 'star');
    expect(order.where((m) => m == 'star').length, 1);

    await _host(tester, _snap(stops: thirty(), busIndex: -1, yourIndex: 25, toGo: 26));
    final fromStart = stripOrder(tester);
    expect(fromStart.where((m) => m != 'bus').length, lessThanOrEqualTo(7));
    expect(fromStart.last, 'star');
  });

  testWidgets("strip: your stop not on the trip shows up to 7 next stops and no star", (tester) async {
    await _host(tester, _snap(stops: thirty(), busIndex: 3, yourIndex: null, toGo: null), minutes: null);
    final order = stripOrder(tester);
    expect(order.contains('star'), isFalse);
    expect(order.where((m) => m != 'bus').length, lessThanOrEqualTo(7));
    expect(order, containsAllInOrder(['dot-3', 'bus', 'dot-4']));
  });

  testWidgets('strip: on arrival the bus sits at your stop and nothing follows it', (tester) async {
    await _host(tester, _snap(stops: thirty(), busIndex: 10, yourIndex: 10, toGo: 0, arrived: true));
    final order = stripOrder(tester);
    expect(order.last, 'star');
    expect(order, ['dot-9', 'bus', 'star']);
  });

  testWidgets('body: during the arrival linger ETAs are scheduled, not shifted by the next trip delay', (tester) async {
    await _host(tester, _snap(busIndex: 1, yourIndex: 1, toGo: 0, arrived: true, schedDiff: -9));
    expect(find.text('12:02 sched'), findsOneWidget);
    expect(find.text('12:11'), findsNothing);
  });

  testWidgets('header: a given route label wins for the badge (linger on a next trip)', (tester) async {
    await _host(tester, _snap(busIndex: 2, toGo: 0, arrived: true), routeLabel: '12');
    expect(find.bySemanticsLabel('Route 12'), findsOneWidget);
    expect(find.bySemanticsLabel('Route 10'), findsNothing);
  });

  testWidgets('screen readers: minutes and scheduled ETAs are spoken in full', (tester) async {
    final semantics = tester.ensureSemantics();
    await _host(tester, _snap(), minutes: 4);
    expect(find.bySemanticsLabel('4 minutes to your stop'), findsOneWidget);
    await _host(tester, _snap(), minutes: 1);
    expect(find.bySemanticsLabel('1 minute to your stop'), findsOneWidget);
    await _host(tester, _snap(), minutes: 0);
    expect(find.bySemanticsLabel('Due now'), findsOneWidget);
    await _host(tester, _snap(schedDiff: null));
    expect(find.bySemanticsLabel('Stop B, 12:01 scheduled'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the strip survives 2x text at the smallest width', (tester) async {
    await _host(tester, _snap(), textScale: 2, width: 320);
    expect(tester.takeException(), isNull);
  });

  group('followEndMessage', () {
    test('words each ending, and says nothing about an arrival', () {
      expect(followEndMessage(FollowEnd.passedYourStop, '2573', 'MUN Centre'), 'Bus 2573 has passed MUN Centre');
      expect(followEndMessage(FollowEnd.passedYourStop, '2573', null), 'Bus 2573 has passed your stop');
      expect(followEndMessage(FollowEnd.tripEnded, '2573', 'MUN Centre'), 'Bus 2573 has finished its trip');
      expect(followEndMessage(FollowEnd.lostContact, '2573', 'MUN Centre'), 'Lost contact with bus 2573');
      expect(followEndMessage(FollowEnd.notFound, '2573', 'MUN Centre'), "Bus 2573 isn't reporting its position");
      expect(followEndMessage(FollowEnd.arrived, '2573', 'MUN Centre'), isNull);
    });
  });
}

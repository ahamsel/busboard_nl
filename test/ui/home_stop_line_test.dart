import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

DateTime _at(int h, int m) => DateTime(testDay.year, testDay.month, testDay.day, h, m);

class _Settings extends SettingsNotifier {
  _Settings(this.stopId);
  final String? stopId;
  @override
  AppSettings build() => AppSettings(selectedStopId: stopId);
}

ArrivalRow _row(int minutes, {bool live = false}) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      minutesAway: minutes,
      isLive: live,
      tripId: 't$minutes',
      vehicleNumber: live ? '2134' : null,
    );

final _line = find.byKey(HomeStopLine.lineKey);
Finder _inLine(Finder f) => find.descendant(of: _line, matching: f);

/// The real home on the test network, your stop C (or [stop]), at [now], its departures from [arrivals].
Future<void> _pump(
  WidgetTester tester, {
  FutureOr<List<ArrivalRow>> Function()? arrivals,
  DateTime? now,
  TestNetwork? net,
  List<ServiceAlert> alerts = const [],
  String? stop = 'C',
  double textScale = 1,
}) =>
    pumpPlannerApp(
      tester,
      net: net ?? TestNetwork(),
      now: now ?? _at(13, 0),
      alerts: alerts,
      textScale: textScale,
      use24h: false,
      overrides: [
        settingsProvider.overrideWith(() => _Settings(stop)),
        stopArrivalsProvider.overrideWith((ref, id) async => arrivals == null ? const <ArrivalRow>[] : await arrivals()),
      ],
    );

void main() {
  setUpAll(loadAppFonts);

  group('what a screen reader hears (spec 2026-10-14 §3.2)', () {
    StopLineInfo next(int minutes, {bool live = true, String? alert}) => StopLineInfo(
          stopName: 'MUN Centre',
          kind: StopLineKind.next,
          route: '10',
          minutes: minutes,
          live: live,
          alertEffect: alert,
        );

    test('live, scheduled, one minute and now', () {
      expect(next(4).semantics(use24h: false), 'Your stop, MUN Centre. Route 10 in 4 minutes, live. Open board');
      expect(next(4, live: false).semantics(use24h: false),
          'Your stop, MUN Centre. Route 10 in 4 minutes, scheduled. Open board');
      expect(next(1).semantics(use24h: false), 'Your stop, MUN Centre. Route 10 in 1 minute, live. Open board');
      expect(next(0).semantics(use24h: false), 'Your stop, MUN Centre. Route 10 arriving now, live. Open board');
    });

    test('no buses, first bus, loading and offline', () {
      const none = StopLineInfo(stopName: 'MUN Centre', kind: StopLineKind.none);
      expect(none.semantics(use24h: false), 'Your stop, MUN Centre. No buses for a while. Open board');
      final first = StopLineInfo(stopName: 'MUN Centre', kind: StopLineKind.firstBus, firstBus: _at(6, 28));
      expect(first.semantics(use24h: false), 'Your stop, MUN Centre. First bus 6:28 AM. Open board');
      const loading = StopLineInfo(stopName: 'MUN Centre', kind: StopLineKind.loading);
      expect(loading.semantics(use24h: false), 'Your stop, MUN Centre. Loading');
      final offline = StopLineInfo(stopName: 'MUN Centre', kind: StopLineKind.offline, updatedAt: _at(9, 42));
      expect(offline.semantics(use24h: false), 'Your stop, MUN Centre. Offline, updated 9:42 AM. Open board');
      expect(offline.note(use24h: false), 'Offline · updated 9:42 AM');
    });

    test('a first bus two or more days away names its weekday, on screen and to a screen reader', () {
      StopLineInfo resolveAt(DateTime now, DateTime first) => StopLineInfo.resolve(
            stopName: 'MUN Centre',
            arrivals: const AsyncData([]),
            firstBus: () => first,
            now: now,
          );
      final friday = DateTime(2026, 10, 9, 22, 0);
      final monday = resolveAt(friday, DateTime(2026, 10, 12, 6, 28));
      expect(monday.note(use24h: false), 'First bus Mon 6:28 AM');
      expect(monday.semantics(use24h: false), 'Your stop, MUN Centre. First bus Mon 6:28 AM. Open board');
      expect(monday.note(use24h: true), 'First bus Mon 06:28');
      // Later today and tomorrow need no day: tomorrow's is the next morning, and the line has no "tomorrow" form.
      final tomorrow = resolveAt(friday, DateTime(2026, 10, 10, 6, 28));
      expect(tomorrow.note(use24h: false), 'First bus 6:28 AM');
      expect(tomorrow.semantics(use24h: false), 'Your stop, MUN Centre. First bus 6:28 AM. Open board');
      final today = resolveAt(DateTime(2026, 10, 9, 4, 0), DateTime(2026, 10, 9, 6, 28));
      expect(today.note(use24h: false), 'First bus 6:28 AM');
    });

    test('an alert on the stop is said right after its name', () {
      expect(next(4, alert: 'Detour').semantics(use24h: false),
          'Your stop, MUN Centre. Detour affects this stop. Route 10 in 4 minutes, live. Open board');
    });

    test('resolve picks the state from the departures', () {
      StopLineInfo resolve(AsyncValue<List<ArrivalRow>> a, {DateTime? first}) =>
          StopLineInfo.resolve(stopName: 'MUN Centre', arrivals: a, firstBus: () => first);
      expect(resolve(const AsyncLoading()).kind, StopLineKind.loading);
      expect(resolve(AsyncError(Exception('down'), StackTrace.empty)).kind, StopLineKind.offline);
      expect(resolve(const AsyncData([])).kind, StopLineKind.none);
      expect(resolve(const AsyncData([]), first: _at(6, 28)).kind, StopLineKind.firstBus);
      final live = resolve(AsyncData([_row(4, live: true), _row(9)]));
      expect((live.kind, live.route, live.minutes, live.live), (StopLineKind.next, '1', 4, true));
    });
  });

  testWidgets('live next bus: route, rolling minutes and the breathing dot', (tester) async {
    await _pump(tester, arrivals: () => [_row(4, live: true)]);
    expect(find.bySemanticsLabel('Your stop, Stop C. Route 1 in 4 minutes, live. Open board'), findsOneWidget);
    expect(_inLine(find.text('Stop C')), findsOneWidget);
    expect(_inLine(find.byType(RouteBadge)), findsOneWidget);
    expect(_inLine(find.byType(BBRollingText)), findsOneWidget);
    expect(_inLine(find.text('4')), findsOneWidget);
    expect(_inLine(find.byType(BBLiveDot)), findsOneWidget);
  });

  testWidgets('scheduled next bus: no dot', (tester) async {
    await _pump(tester, arrivals: () => [_row(4)]);
    expect(find.bySemanticsLabel('Your stop, Stop C. Route 1 in 4 minutes, scheduled. Open board'), findsOneWidget);
    expect(_inLine(find.byType(BBLiveDot)), findsNothing);
  });

  testWidgets('"Now" in the soon colour, with no minute unit', (tester) async {
    await _pump(tester, arrivals: () => [_row(0, live: true)]);
    expect(find.bySemanticsLabel('Your stop, Stop C. Route 1 arriving now, live. Open board'), findsOneWidget);
    expect(tester.widget<Text>(_inLine(find.text('Now'))).style!.color, BBColors.light.soon);
    expect(_inLine(find.text(' min')), findsNothing);
  });

  testWidgets('no bus within three hours, and not a first bus: "No buses for a while"', (tester) async {
    // Stop C's morning buses are gone by 09:30 and the next leaves at 14:00: a gap, not a first bus.
    final net = TestNetwork()..addTrip('2-late', '2', ['C', 'D'], 14 * 3600, 240);
    await _pump(tester, net: net, now: _at(9, 30));
    expect(_inLine(find.text(' · No buses for a while')), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. No buses for a while. Open board'), findsOneWidget);
  });

  testWidgets("at night: tomorrow's first bus", (tester) async {
    await _pump(tester, now: _at(22, 0));
    expect(_inLine(find.text(' · First bus 8:05 AM')), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. First bus 8:05 AM. Open board'), findsOneWidget);
  });

  testWidgets("on a Friday night with no weekend service: Monday's first bus, with its day", (tester) async {
    final net = TestNetwork();
    final every = net.repo.calendarsById[TestNetwork.serviceId]!;
    net.repo.calendarsById[TestNetwork.serviceId] = ServiceCalendar(
      serviceId: every.serviceId,
      monday: true,
      tuesday: true,
      wednesday: true,
      thursday: true,
      friday: true,
      saturday: false,
      sunday: false,
      startDate: every.startDate,
      endDate: every.endDate,
    );
    // testDay is a Wednesday: two days on is Friday.
    await _pump(tester, net: net, now: DateTime(testDay.year, testDay.month, testDay.day + 2, 22, 0));
    expect(_inLine(find.text(' · First bus Mon 8:05 AM')), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. First bus Mon 8:05 AM. Open board'), findsOneWidget);
  });

  testWidgets('loading: the name and a shimmer where the time goes', (tester) async {
    await _pump(tester, arrivals: () => Completer<List<ArrivalRow>>().future);
    expect(_inLine(find.byType(BBSkeleton)), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. Loading'), findsOneWidget);
  });

  testWidgets('offline: when the departures last loaded', (tester) async {
    await _pump(tester, arrivals: () => throw Exception('offline'));
    // Riverpod retries a failed provider with backoff before surfacing the error.
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_inLine(find.text(' · Offline')), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
        .read(stopArrivalsUpdatedAtProvider.notifier)
        .stamp('C', _at(9, 42));
    await tester.pumpAndSettle();
    expect(_inLine(find.text(' · Offline · updated 9:42 AM')), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. Offline, updated 9:42 AM. Open board'), findsOneWidget);
  });

  testWidgets('a refresh that fails after a good load says Offline, not the old minutes', (tester) async {
    var calls = 0;
    await _pump(tester, arrivals: () {
      if (calls++ == 0) return [_row(4, live: true)];
      throw Exception('offline');
    });
    expect(_inLine(find.text('4')), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen))).invalidate(stopArrivalsProvider('C'));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_inLine(find.textContaining('Offline')), findsOneWidget);
    expect(_inLine(find.text('4')), findsNothing);
  });

  testWidgets('at 3x text on 320 pt the line still fits: the time shrinks rather than truncate', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, arrivals: () => [_row(12, live: true)], textScale: 3);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(_line).right, lessThanOrEqualTo(320));
    expect(tester.renderObject<RenderParagraph>(_inLine(find.text('12'))).didExceedMaxLines, isFalse);
  });

  testWidgets('an alert affecting the stop: a gold mark after its name', (tester) async {
    await _pump(
      tester,
      arrivals: () => [_row(4, live: true)],
      alerts: [
        ServiceAlert(
          sourceIds: const {'d'},
          header: 'Stop C moved',
          description: '',
          cause: ServiceAlertCause.construction,
          effect: ServiceAlertEffect.detour,
          severity: ServiceAlertSeverity.warning,
          activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
          targets: const [ServiceAlertTarget(stopId: 'C')],
        ),
      ],
    );
    final mark = _inLine(find.byKey(const ValueKey('home-stop-line-alert')));
    expect(mark, findsOneWidget);
    expect(tester.widget<Icon>(mark).color, BBColors.light.warnInk);
    expect(
      find.bySemanticsLabel('Your stop, Stop C. Detour affects this stop. Route 1 in 4 minutes, live. Open board'),
      findsOneWidget,
    );
  });

  group("the alert mark takes the stop's most important alert (final review M5)", () {
    ServiceAlert alert(
      ServiceAlertEffect effect, {
      ServiceAlertSeverity severity = ServiceAlertSeverity.unknown,
      List<ServiceAlertTarget> targets = const [ServiceAlertTarget(stopId: 'C')],
    }) =>
        ServiceAlert(
          sourceIds: {effect.name},
          header: effect.label,
          description: '',
          cause: ServiceAlertCause.unknown,
          effect: effect,
          severity: severity,
          activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
          targets: targets,
        );
    const agency = [ServiceAlertTarget(agencyId: 'metrobus')];

    test('Information and Additional service never mark the stop', () {
      expect(stopLineAlert([alert(ServiceAlertEffect.noEffect)], routes: {'1'}, stopId: 'C'), isNull);
      expect(stopLineAlert([alert(ServiceAlertEffect.additionalService)], routes: {'1'}, stopId: 'C'), isNull);
    });

    test('an agency-wide info alert does not mark the stop', () {
      expect(
        stopLineAlert([alert(ServiceAlertEffect.other, severity: ServiceAlertSeverity.info, targets: agency)],
            routes: {'1'}, stopId: 'C'),
        isNull,
      );
      expect(
        stopLineAlert([alert(ServiceAlertEffect.noEffect, targets: const [])], routes: {'1'}, stopId: 'C'),
        isNull,
      );
    });

    test('an agency-wide warning still does', () {
      final strike = alert(ServiceAlertEffect.noService, severity: ServiceAlertSeverity.severe, targets: agency);
      expect(stopLineAlert([strike], routes: {'1'}, stopId: 'C'), strike);
    });

    test('the highest priority wins, whatever the feed order', () {
      final info = alert(ServiceAlertEffect.noEffect);
      final moved = alert(ServiceAlertEffect.stopMoved);
      final none = alert(ServiceAlertEffect.noService);
      expect(stopLineAlert([info, moved, none], routes: {'1'}, stopId: 'C'), none);
    });

    test('an alert for another stop or route is left out', () {
      expect(
        stopLineAlert([alert(ServiceAlertEffect.detour, targets: const [ServiceAlertTarget(stopId: 'X')])],
            routes: {'1'}, stopId: 'C'),
        isNull,
      );
    });

    testWidgets('an Information alert listed first: the line names the detour after it', (tester) async {
      await _pump(
        tester,
        arrivals: () => [_row(4, live: true)],
        alerts: [alert(ServiceAlertEffect.noEffect), alert(ServiceAlertEffect.detour)],
      );
      expect(_inLine(find.byKey(const ValueKey('home-stop-line-alert'))), findsOneWidget);
      expect(
        find.bySemanticsLabel('Your stop, Stop C. Detour affects this stop. Route 1 in 4 minutes, live. Open board'),
        findsOneWidget,
      );
    });

    testWidgets('only an Information alert: no mark', (tester) async {
      await _pump(tester, arrivals: () => [_row(4, live: true)], alerts: [alert(ServiceAlertEffect.noEffect)]);
      expect(_inLine(find.byKey(const ValueKey('home-stop-line-alert'))), findsNothing);
    });
  });

  testWidgets('no stop chosen: "Choose your stop"', (tester) async {
    await _pump(tester, stop: null);
    expect(_inLine(find.text('Choose your stop')), findsOneWidget);
    expect(find.bySemanticsLabel('Choose your stop'), findsOneWidget);
  });

  for (final (what, arrivals, now) in [
    ('the next bus', () => [_row(12, live: true)], _at(13, 0)),
    ('the first bus', () => const <ArrivalRow>[], _at(22, 0)),
  ]) {
    testWidgets('at 2x text on 320 pt the long name truncates first, never $what', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final net = TestNetwork();
      net.repo.stopsById['C'] =
          const StopInfo(stopId: 'C', stopName: 'Memorial University Centre Bus Terminal', stopLat: 47.57, stopLon: -52.75);
      await _pump(tester, net: net, now: now, arrivals: arrivals, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(_line).right, lessThanOrEqualTo(320));
      final name = tester.renderObject<RenderParagraph>(_inLine(find.text('Memorial University Centre Bus Terminal')));
      expect(name.didExceedMaxLines, isTrue, reason: 'the name gives way');
      final time = _inLine(find.text(what == 'the next bus' ? '12' : ' · First bus 8:05 AM'));
      expect(time, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(time).didExceedMaxLines, isFalse, reason: 'the time reads in full');
    });
  }
}

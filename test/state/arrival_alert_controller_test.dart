// test/state/arrival_alert_controller_test.dart
import 'dart:async';

import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/data/arrival_alerts/alert_store.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:busboard_nl/state/providers.dart' show recentLiveFeedProvider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../helpers/feed_fixtures.dart';

class FakeNotifications implements AlertNotifications {
  FakeNotifications({this.grant = true});
  bool grant;
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => grant;
  @override
  Future<bool> requestPermission() async => grant;
  @override
  Future<void> show(AlertMessage m) async {}
  @override
  Future<void> schedule(AlertMessage m, DateTime at) async {}
  @override
  Future<void> cancelScheduled() async {}
  @override
  Future<String?> launchRoute() async => null;
}

class FakeRunner implements AlertRunner {
  FakeRunner({this.watchesLive = false});
  @override
  final bool watchesLive;
  final started = <ArrivalAlert>[];
  final updated = <ArrivalAlert>[];
  final backgrounded = <ArrivalAlert>[];
  final ensured = <ArrivalAlert>[];
  int stops = 0;
  Completer<void>? stopGate;
  bool throwOnStart = false;
  final finishedController = StreamController<void>.broadcast();
  @override
  Stream<void> get finished => finishedController.stream;
  @override
  Future<void> start(ArrivalAlert alert) async {
    if (throwOnStart) throw Exception('service failed to start');
    started.add(alert);
  }
  @override
  Future<void> update(ArrivalAlert alert) async => updated.add(alert);
  @override
  Future<void> onBackground(ArrivalAlert alert) async => backgrounded.add(alert);
  @override
  Future<void> ensureRunning(ArrivalAlert alert) async => ensured.add(alert);
  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
  }
}

/// The open GTFS-RT feeds as the iPhone re-timer reads them: counts its fetches.
class FakeFeed {
  int calls = 0;
  TimeTrackFetchResult result = const TimeTrackFetchResult.failure(error: 'offline');
  Future<TimeTrackFetchResult> call() async {
    calls++;
    return result;
  }
}

final now = DateTime(2026, 10, 6, 8, 0);
ArrivalRow row({int predicted = 8 * 3600 + 14 * 60, String trip = 't1'}) => ArrivalRow(
      routeShortName: '10',
      headsign: 'MUN-CNA-MI',
      scheduledTime: GtfsTime.fromSeconds(8 * 3600 + 12 * 60),
      predictedTime: GtfsTime.fromSeconds(predicted),
      minutesAway: (predicted - 8 * 3600) ~/ 60,
      isLive: true,
      tripId: trip,
      vehicleNumber: '1415',
      routeRun: '10-4',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRunner runner;
  late FakeNotifications notes;
  late DateTime clock;
  late FakeFeed feed;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      alertRunnerProvider.overrideWithValue(runner),
      alertNotificationsProvider.overrideWithValue(notes),
      alertClockProvider.overrideWithValue(() => clock),
      alertLiveFeedProvider.overrideWithValue(feed.call),
      alertRetimeEveryProvider.overrideWithValue(const Duration(milliseconds: 20)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    runner = FakeRunner();
    notes = FakeNotifications();
    clock = now;
    feed = FakeFeed();
  });

  test('set stores the alert, remembers the lead and starts the runner', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    final result = await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 10);
    expect(result, SetAlertResult.set);
    expect(c.read(arrivalAlertProvider).value!.tripId, 't1');
    expect((await AlertStore().read())!.leadMinutes, 10);
    expect(await AlertStore().lastLead(), 10);
    expect(runner.started.single.expectedAt, DateTime(2026, 10, 6, 8, 14));
  });

  test('permission denied: nothing stored, nothing started', () async {
    notes.grant = false;
    final c = container();
    await c.read(arrivalAlertProvider.future);
    final result = await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    expect(result, SetAlertResult.permissionDenied);
    expect(c.read(arrivalAlertProvider).value, isNull);
    expect(await AlertStore().read(), isNull);
    expect(runner.started, isEmpty);
  });

  test('cancel stops the runner and clears everything', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    await c.read(arrivalAlertProvider.notifier).cancel();
    expect(runner.stops, 1);
    expect(c.read(arrivalAlertProvider).value, isNull);
    expect(await AlertStore().read(), isNull);
  });

  test('a Board refresh while cancelling does not re-time the cancelled alert', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    final ctl = c.read(arrivalAlertProvider.notifier);
    await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    final gate = runner.stopGate = Completer<void>();
    final cancelling = ctl.cancel();
    expect(c.read(arrivalAlertProvider).value, isNull);
    ctl.onBoardArrivals('1150', [row(predicted: 8 * 3600 + 18 * 60)]);
    gate.complete();
    await cancelling;
    await Future<void>.delayed(Duration.zero);
    expect(runner.updated, isEmpty);
    expect(await AlertStore().read(), isNull);
  });

  test('the runner failing to start: nothing stored, no alert, and the caller is told', () async {
    runner.throwOnStart = true;
    final c = container();
    await c.read(arrivalAlertProvider.future);
    final result = await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    expect(result, SetAlertResult.failed);
    expect(c.read(arrivalAlertProvider).value, isNull);
    expect(await AlertStore().read(), isNull);
    expect(runner.stops, 1, reason: 'a backup armed before the failure is cancelled');
  });

  test('a stored alert comes back after an app restart', () async {
    await AlertStore().write(ArrivalAlert.fromArrival(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: now));
    final c = container();
    expect((await c.read(arrivalAlertProvider.future))!.tripId, 't1');
  });

  test('a stale stored alert (past its window) is cleared at launch', () async {
    await AlertStore().write(ArrivalAlert.fromArrival(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5,
        now: now.subtract(const Duration(hours: 3))));
    final c = container();
    expect(await c.read(arrivalAlertProvider.future), isNull);
    expect(await AlertStore().read(), isNull);
  });

  test('the runner finishing clears the alert', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    await AlertStore().clear();
    runner.finishedController.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(arrivalAlertProvider).value, isNull);
  });

  test('iPhone: a newer Board prediction re-times and re-schedules', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    c.read(arrivalAlertProvider.notifier).onBoardArrivals('1150', [row(predicted: 8 * 3600 + 18 * 60)]);
    await Future<void>.delayed(Duration.zero);
    expect(runner.updated.single.expectedAt, DateTime(2026, 10, 6, 8, 18));
  });

  test('Android: the Board never re-times a watched alert', () async {
    runner = FakeRunner(watchesLive: true);
    final c = container();
    await c.read(arrivalAlertProvider.future);
    await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    c.read(arrivalAlertProvider.notifier).onBoardArrivals('1150', [row(predicted: 8 * 3600 + 18 * 60)]);
    await Future<void>.delayed(Duration.zero);
    expect(runner.updated, isEmpty);
  });

  group('a watcher the phone ended (reboot, force-stop, battery saver)', () {
    ArrivalAlert stored({DateTime? at}) =>
        ArrivalAlert.fromArrival(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: at ?? now);

    setUp(() => runner = FakeRunner(watchesLive: true));

    test('is made sure of when the app finds a stored live alert', () async {
      await AlertStore().write(stored());
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(runner.ensured.single.tripId, 't1');
    });

    test('not with no alert', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(runner.ensured, isEmpty);
    });

    test('not for a stale alert', () async {
      await AlertStore().write(stored(at: now.subtract(const Duration(hours: 3))));
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(runner.ensured, isEmpty);
    });

    test('not for an alert that has fired', () async {
      await AlertStore().write(stored().copyWith(firedAt: DateTime(2026, 10, 6, 8, 9)));
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(runner.ensured, isEmpty);
    });

    test('not on iPhone, where the controller already delivers the alert once', () async {
      runner = FakeRunner();
      await AlertStore().write(stored());
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(runner.ensured, isEmpty);
    });

    testWidgets('again when the app comes back to the foreground', (tester) async {
      final c = container();
      await tester.runAsync(() => c.read(arrivalAlertProvider.future));
      await AlertStore().write(stored());
      final binding = tester.binding;
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        binding.handleAppLifecycleStateChanged(s);
      }
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        binding.handleAppLifecycleStateChanged(s);
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(runner.ensured.single.tripId, 't1');
    });
  });

  group('a restart after the backup alert was delivered (Android)', () {
    // Expected 08:14, lead 5: alertAt 08:08 (with the 1 min margin), the backup fires at 08:10.
    ArrivalAlert stored() => ArrivalAlert.fromArrival(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: now);
    final backupAt = DateTime(2026, 10, 6, 8, 10);

    setUp(() => runner = FakeRunner(watchesLive: true));

    test('at launch the alert counts as fired, and no watcher restarts it', () async {
      await AlertStore().write(stored());
      clock = DateTime(2026, 10, 6, 8, 12); // alertAt was 4 min ago
      final c = container();
      final a = await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(runner.ensured, isEmpty);
      expect(runner.started, isEmpty);
      expect(a!.firedAt, backupAt);
      expect(c.read(arrivalAlertProvider).value!.firedAt, backupAt);
      expect((await AlertStore().read())!.firedAt, backupAt);
    });

    test('exactly at the backup time it counts as fired', () async {
      await AlertStore().write(stored());
      clock = backupAt;
      final c = container();
      final a = await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(runner.ensured, isEmpty);
      expect(a!.firedAt, backupAt);
    });

    test('before the backup time the watcher is made sure of, as before', () async {
      await AlertStore().write(stored());
      clock = DateTime(2026, 10, 6, 8, 9); // alertAt was 1 min ago
      final c = container();
      final a = await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(runner.ensured, hasLength(1));
      expect(a!.firedAt, isNull);
      expect((await AlertStore().read())!.firedAt, isNull);
    });

    Future<void> resume(WidgetTester tester) async {
      final binding = tester.binding;
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        binding.handleAppLifecycleStateChanged(s);
      }
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        binding.handleAppLifecycleStateChanged(s);
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    testWidgets('on resume the alert counts as fired, and no watcher restarts it', (tester) async {
      final c = container();
      await tester.runAsync(() => c.read(arrivalAlertProvider.future));
      await tester.runAsync(() => AlertStore().write(stored()));
      clock = DateTime(2026, 10, 6, 8, 12);
      await resume(tester);
      expect(runner.ensured, isEmpty);
      expect(c.read(arrivalAlertProvider).value!.firedAt, backupAt);
      expect((await tester.runAsync(() => AlertStore().read()))!.firedAt, backupAt);
    });

    testWidgets('on resume before the backup time the watcher is made sure of', (tester) async {
      final c = container();
      await tester.runAsync(() => c.read(arrivalAlertProvider.future));
      await tester.runAsync(() => AlertStore().write(stored()));
      clock = DateTime(2026, 10, 6, 8, 9);
      await resume(tester);
      expect(runner.ensured, hasLength(1));
      expect(c.read(arrivalAlertProvider).value!.firedAt, isNull);
    });
  });

  group('iPhone fires exactly once', () {
    final alertAt = DateTime(2026, 10, 6, 8, 8); // expected 08:14, lead 5, 1 min margin

    test('a Board re-time after the alert time has passed records firedAt and does not update', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      final ctl = c.read(arrivalAlertProvider.notifier);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 9); // the OS already showed the 08:08 notification
      ctl.onBoardArrivals('1150', [row(predicted: 8 * 3600 + 18 * 60)]);
      await Future<void>.delayed(Duration.zero);
      expect(runner.updated, isEmpty);
      expect(c.read(arrivalAlertProvider).value!.firedAt, alertAt);
      expect((await AlertStore().read())!.firedAt, alertAt);
    });

    test('a re-time that moves the alert time into the past updates once, records firedAt, then stays quiet', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      final ctl = c.read(arrivalAlertProvider.notifier);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 7); // before 08:08, but the bus now looks due at 08:12 (alert 08:06)
      ctl.onBoardArrivals('1150', [row(predicted: 8 * 3600 + 12 * 60)]);
      await Future<void>.delayed(Duration.zero);
      expect(runner.updated, hasLength(1));
      expect(c.read(arrivalAlertProvider).value!.firedAt, clock);
      expect((await AlertStore().read())!.firedAt, clock);

      ctl.onBoardArrivals('1150', [row(predicted: 8 * 3600 + 11 * 60)]);
      await Future<void>.delayed(Duration.zero);
      expect(runner.updated, hasLength(1));
    });

    test('with firedAt set, the Board changes nothing', () async {
      await AlertStore().write(
          ArrivalAlert.fromArrival(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: now).copyWith(firedAt: alertAt));
      final c = container();
      await c.read(arrivalAlertProvider.future);
      clock = DateTime(2026, 10, 6, 8, 1);
      c.read(arrivalAlertProvider.notifier).onBoardArrivals('1150', [row(predicted: 8 * 3600 + 18 * 60)]);
      await Future<void>.delayed(Duration.zero);
      expect(runner.updated, isEmpty);
      expect(c.read(arrivalAlertProvider).value!.expectedAt, DateTime(2026, 10, 6, 8, 14));
    });

    test('pausing before the alert time hands the alert to the runner', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      final ctl = c.read(arrivalAlertProvider.notifier);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      await ctl.onAppPaused();
      expect(runner.backgrounded, hasLength(1));
      expect(c.read(arrivalAlertProvider).value!.firedAt, isNull);
    });

    test('pausing after the alert time records firedAt and does not call the runner', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      final ctl = c.read(arrivalAlertProvider.notifier);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 10);
      await ctl.onAppPaused();
      expect(runner.backgrounded, isEmpty);
      expect(c.read(arrivalAlertProvider).value!.firedAt, alertAt);
      expect((await AlertStore().read())!.firedAt, alertAt);
    });

    test('pausing with firedAt set does nothing', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      final ctl = c.read(arrivalAlertProvider.notifier);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 10);
      await ctl.onAppPaused();
      await ctl.onAppPaused();
      expect(runner.backgrounded, isEmpty);
    });

    test('Android: pausing still calls the runner, with no firedAt bookkeeping', () async {
      runner = FakeRunner(watchesLive: true);
      final c = container();
      await c.read(arrivalAlertProvider.future);
      final ctl = c.read(arrivalAlertProvider.notifier);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 10);
      await ctl.onAppPaused();
      expect(runner.backgrounded, hasLength(1));
      expect(c.read(arrivalAlertProvider).value!.firedAt, isNull);
    });

    test('pausing with no alert does nothing', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await c.read(arrivalAlertProvider.notifier).onAppPaused();
      expect(runner.backgrounded, isEmpty);
    });
  });

  group('iPhone: the alert keeps being re-timed whichever tab or page is showing', () {
    // Several re-time intervals (20 ms in these tests).
    Future<void> ticks() => Future<void>.delayed(const Duration(milliseconds: 90));
    TimeTrackFetchResult sixBehind() => fakeFeed([fakeVehicle(fix: clock.subtract(const Duration(seconds: 20)))]);

    test('with no Board or trip page feeding it, the live feed re-times and re-schedules it', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 1);
      feed.result = sixBehind();
      await ticks();
      expect(feed.calls, greaterThanOrEqualTo(1));
      expect(runner.updated.single.expectedAt, DateTime(2026, 10, 6, 8, 18), reason: 'scheduled 08:12, 6 min behind');
      expect(c.read(arrivalAlertProvider).value!.expectedAt, DateTime(2026, 10, 6, 8, 18));
      expect((await AlertStore().read())!.expectedAt, DateTime(2026, 10, 6, 8, 18));
    });

    test('a Board refresh within the interval spares the fetch', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      final ctl = c.read(arrivalAlertProvider.notifier);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 1);
      ctl.onBoardArrivals('1150', [row(predicted: 8 * 3600 + 18 * 60)]);
      await ticks();
      expect(feed.calls, 0, reason: 'the Board on screen already re-times it');
    });

    test('a stored alert found at launch is re-timed at once', () async {
      await AlertStore().write(ArrivalAlert.fromArrival(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: now));
      clock = DateTime(2026, 10, 6, 8, 1);
      feed.result = sixBehind();
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(feed.calls, 1);
      expect(runner.updated.single.expectedAt, DateTime(2026, 10, 6, 8, 18));
    });

    test('in the background it stops (the scheduler has its last word), and on return it fetches again', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 1);
      final binding = TestWidgetsFlutterBinding.instance;
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        binding.handleAppLifecycleStateChanged(s);
      }
      await ticks();
      expect(feed.calls, 0);
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        binding.handleAppLifecycleStateChanged(s);
      }
      await ticks();
      expect(feed.calls, greaterThanOrEqualTo(1));
    });

    test('a failed fetch or no live bus leaves the alert as it is', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 1);
      await ticks();
      feed.result = fakeFeed([fakeVehicle(trip: 't2', fix: clock)]);
      await ticks();
      expect(feed.calls, greaterThanOrEqualTo(2));
      expect(runner.updated, isEmpty);
      expect(c.read(arrivalAlertProvider).value!.expectedAt, DateTime(2026, 10, 6, 8, 14));
    });

    test('past the alert time, or once cancelled, nothing is fetched', () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      final ctl = c.read(arrivalAlertProvider.notifier);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 8); // the alert time: the OS shows the notification
      await ticks();
      expect(feed.calls, 0);
      clock = DateTime(2026, 10, 6, 8, 1);
      await ctl.set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      await ctl.cancel();
      clock = DateTime(2026, 10, 6, 8, 2);
      await ticks();
      expect(feed.calls, 0);
    });

    test("the map's own poll of the feed, a moment ago, re-times it without a second fetch", () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 1);
      // The map polls more often than the re-timer would (5 s against 30 s; here 5 ms against 20 ms).
      final mapPolls = Timer.periodic(const Duration(milliseconds: 5),
          (_) => c.read(recentLiveFeedProvider.notifier).record(DateTime.now(), sixBehind()));
      addTearDown(mapPolls.cancel);
      c.read(recentLiveFeedProvider.notifier).record(DateTime.now(), sixBehind());
      await ticks();
      expect(feed.calls, 0, reason: 'the Map tab polled the feed already');
      expect(runner.updated.single.expectedAt, DateTime(2026, 10, 6, 8, 18));
    });

    test("a poll older than the re-time interval doesn't count: the re-timer fetches", () async {
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 1);
      c.read(recentLiveFeedProvider.notifier).record(DateTime.now().subtract(const Duration(minutes: 1)), sixBehind());
      await ticks();
      expect(feed.calls, greaterThanOrEqualTo(1));
    });

    test('Android: the watcher re-times it, so the app fetches nothing', () async {
      runner = FakeRunner(watchesLive: true);
      final c = container();
      await c.read(arrivalAlertProvider.future);
      await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
      clock = DateTime(2026, 10, 6, 8, 1);
      await ticks();
      expect(feed.calls, 0);
    });
  });
}

// lib/state/arrival_alert_providers.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/arrival_alerts/alert_notifications.dart';
import '../data/arrival_alerts/alert_store.dart';
import '../data/realtime/timetrack_api.dart';
import '../domain/arrival/arrival_models.dart';
import '../domain/arrival_alerts/alert_tracker.dart';
import '../domain/arrival_alerts/arrival_alert.dart';
import '../domain/arrival_alerts/gtfs_rt_source.dart';
import '../platform/alert_runner.dart';
import '../platform/android_alert_watcher.dart';
import '../platform/ios_alert_scheduler.dart';
import '../routing/notification_route.dart';
import 'providers.dart' show timetrackApiProvider;

final alertStoreProvider = Provider<AlertStore>((ref) => AlertStore());
final alertNotificationsProvider = Provider<AlertNotifications>((ref) => LocalAlertNotifications(onOpen: openAlertRoute));
final alertClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// What the iPhone re-timer reads: the open GTFS-RT feeds, as the Android watcher does.
final alertLiveFeedProvider =
    Provider<Future<TimeTrackFetchResult> Function()>((ref) => ref.read(timetrackApiProvider).fetchLiveVehiclesResult);

/// How often the iPhone re-timer checks the live feed when no Board or trip page has fed the alert a newer time.
final alertRetimeEveryProvider = Provider<Duration>((ref) => const Duration(seconds: 30));

final alertRunnerProvider = Provider<AlertRunner>((ref) {
  final notifications = ref.watch(alertNotificationsProvider);
  if (defaultTargetPlatform == TargetPlatform.android) return AndroidAlertRunner(notifications, onOpen: openAlertRoute);
  return IosAlertRunner(AlertScheduler(
    notifications: notifications,
    clock: ref.watch(alertClockProvider),
    use24h: () => PlatformDispatcher.instance.alwaysUse24HourFormat,
  ));
});

enum SetAlertResult {
  set,
  permissionDenied,

  /// The platform could not start the alert; nothing is set.
  failed,
}

/// The one active arrival alert (spec §2).
final arrivalAlertProvider =
    AsyncNotifierProvider<ArrivalAlertController, ArrivalAlert?>(ArrivalAlertController.new);

class ArrivalAlertController extends AsyncNotifier<ArrivalAlert?> {
  AlertStore get _store => ref.read(alertStoreProvider);
  AlertRunner get _runner => ref.read(alertRunnerProvider);
  DateTime _now() => ref.read(alertClockProvider)();

  /// iPhone: re-times the armed alert from the live feed, whichever tab or page shows (the Board and a trip's steps
  /// stop polling behind other tabs). Runs while the app is in front; the scheduler has the last word on pause.
  Timer? _retimer;
  bool _foreground = true;
  bool _fetching = false;

  /// When a Board or a trip's steps last gave the alert's stop fresh rows: the re-timer need not fetch until later.
  DateTime? _fedAt;

  @override
  Future<ArrivalAlert?> build() async {
    final sub = _runner.finished.listen((_) async {
      await _store.clear();
      state = const AsyncData(null);
    });
    final lifecycle = AppLifecycleListener(
      onPause: () {
        _foreground = false;
        _syncRetimer();
        unawaited(onAppPaused());
      },
      onResume: () {
        _foreground = true;
        unawaited(_reload());
      },
    );
    listenSelf((_, _) => _syncRetimer());
    ref.onDispose(() {
      unawaited(sub.cancel());
      lifecycle.dispose();
      _retimer?.cancel();
      _retimer = null;
    });
    return _settle(await _loadFresh());
  }

  /// Runs the re-timer while an iPhone alert waits for its time with the app in front; on (re)start it checks at once.
  void _syncRetimer() {
    final a = state.value;
    final wanted = _foreground && a != null && a.firedAt == null && !_runner.watchesLive && _now().isBefore(a.alertAt);
    if (!wanted) {
      _retimer?.cancel();
      _retimer = null;
      return;
    }
    if (_retimer != null) return;
    _retimer = Timer.periodic(ref.read(alertRetimeEveryProvider), (_) => unawaited(_retimeFromFeed()));
    unawaited(_retimeFromFeed());
  }

  Future<void> _retimeFromFeed() async {
    final a = state.value;
    if (a == null || a.firedAt != null || _fetching) return;
    final now = _now();
    if (!now.isBefore(a.alertAt)) {
      // The OS shows the notification scheduled for this time; nothing left to re-time.
      _syncRetimer();
      return;
    }
    final fed = _fedAt;
    if (fed != null && now.difference(fed) < ref.read(alertRetimeEveryProvider)) return;
    _fetching = true;
    TimeTrackFetchResult? feed;
    try {
      feed = await ref.read(alertLiveFeedProvider)();
    } catch (_) {
      feed = null;
    } finally {
      _fetching = false;
    }
    if (!ref.mounted) return;
    final current = state.value;
    // Cancelled, replaced or fired while the request was in flight.
    if (current == null || !current.isSameAlert(a) || current.firedAt != null) return;
    final at = _now();
    final departures = liveResultForAlert(current, feed, at).departures;
    if (departures.isEmpty) return;
    final d = departures.first;
    final predicted = d.predictedGtfsTime ?? d.scheduledGtfsTime;
    if (predicted != null) _retime(current, instantOfServiceTime(predicted, at), at);
  }

  /// Hands the alert re-timed to [expectedAt] (a live prediction seen at [now]) to the iPhone scheduler.
  void _retime(ArrivalAlert a, DateTime expectedAt, DateTime now) {
    final retimed = a.copyWith(expectedAt: expectedAt, live: true, lastSeenAt: now);
    if (retimed.expectedAt == a.expectedAt) return;
    unawaited(_deliverOnce(a, retimed, _runner.update));
  }

  Future<ArrivalAlert?> _loadFresh() async {
    final a = await _store.read();
    if (a == null) return null;
    final now = _now();
    final stale = now.difference(a.setAt) >= AlertTracker.maxRun ||
        now.isAfter(a.expectedAt.add(const Duration(minutes: 2)));
    if (!stale) return a;
    await _store.clear();
    return null;
  }

  Future<void> _reload() async {
    state = AsyncData(await _settle(await _loadFresh()));
  }

  /// A stored Android alert that has not fired needs its watcher: a reboot, force-stop or battery saver
  /// ends it. Not once the OS has delivered the backup notification, though: the backup never writes
  /// `firedAt`, and a watcher restarted then would see the alert time long past and fire a second time.
  /// So from the backup time on, the alert counts as fired, at that time. Returns the alert to show.
  Future<ArrivalAlert?> _settle(ArrivalAlert? a) async {
    if (a == null || a.firedAt != null || !_runner.watchesLive) return a;
    final backupAt = a.alertAt.add(backupGrace);
    if (!_now().isBefore(backupAt)) {
      final fired = a.copyWith(firedAt: backupAt);
      await _store.write(fired);
      return fired;
    }
    unawaited(_runner.ensureRunning(a).catchError((Object _) {}));
    return a;
  }

  Future<int> lastLead() => _store.lastLead();

  Future<bool> permissionGranted() => ref.read(alertNotificationsProvider).permissionGranted();

  Future<SetAlertResult> set(ArrivalRow row, {required String stopId, required String stopName, required int leadMinutes}) async {
    if (!await ref.read(alertNotificationsProvider).requestPermission()) return SetAlertResult.permissionDenied;
    final alert = ArrivalAlert.fromArrival(row, stopId: stopId, stopName: stopName, leadMinutes: leadMinutes, now: _now());
    await _store.write(alert);
    await _store.saveLead(leadMinutes);
    // Set from the Board's fresh rows: the re-timer need not fetch at once.
    _fedAt = _now();
    try {
      await _runner.start(alert);
    } catch (_) {
      // A half-started alert may have armed its backup.
      try {
        await _runner.stop();
      } catch (_) {}
      await _store.clear();
      state = const AsyncData(null);
      return SetAlertResult.failed;
    }
    state = AsyncData(alert);
    return SetAlertResult.set;
  }

  Future<void> cancel() async {
    // Before any await, so a Board refresh meanwhile finds no alert to re-time.
    state = const AsyncData(null);
    await _runner.stop();
    await _store.clear();
  }

  /// The Board (or a trip's steps) refreshed [stopId]. On iPhone a newer live prediction re-times the alert.
  void onBoardArrivals(String stopId, List<ArrivalRow> rows) {
    final a = state.value;
    if (a == null || a.stopId != stopId || _runner.watchesLive) return;
    _fedAt = _now();
    for (final r in rows) {
      if (r.tripId != a.tripId || !r.isLive || r.predictedTime == null) continue;
      final now = _now();
      _retime(a, instantOfServiceTime(r.displayTime, now), now);
      return;
    }
  }

  /// The app is going to the background: the iPhone scheduler gets its last word in. Android's
  /// watcher keeps running by itself, so there it is a no-op.
  Future<void> onAppPaused() async {
    final a = state.value;
    if (a == null) return;
    if (_runner.watchesLive) {
      await _runner.onBackground(a);
      return;
    }
    await _deliverOnce(a, a, _runner.onBackground);
  }

  /// Hands [next] (the [stored] alert, maybe re-timed) to a runner that does not watch live, so that
  /// the alert fires exactly once. The iPhone scheduler shows an alert again each time it is given
  /// one whose time has passed, so the controller remembers when it fired.
  ///
  /// Everything up to the first `await` runs synchronously, so a second Board refresh sees the state.
  Future<void> _deliverOnce(ArrivalAlert stored, ArrivalAlert next, Future<void> Function(ArrivalAlert) send) async {
    if (next.firedAt != null) return;
    final now = _now();
    if (!now.isBefore(stored.alertAt)) {
      // The OS already showed the notification scheduled for the old time.
      await _markFired(next, stored.alertAt);
      return;
    }
    state = AsyncData(next);
    if (!identical(next, stored)) unawaited(_store.write(next));
    await send(next);
    // The scheduler shows an alert at once when its time is already past.
    if (!now.isBefore(next.alertAt)) await _markFired(next, now);
  }

  Future<void> _markFired(ArrivalAlert alert, DateTime at) async {
    final current = state.value;
    // Cancelled, replaced or already marked while the runner was working.
    if (current == null || !current.isSameAlert(alert) || current.firedAt != null) return;
    final fired = alert.copyWith(firedAt: at);
    state = AsyncData(fired);
    await _store.write(fired);
  }
}

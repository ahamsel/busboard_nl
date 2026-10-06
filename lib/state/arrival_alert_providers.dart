// lib/state/arrival_alert_providers.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/arrival_alerts/alert_notifications.dart';
import '../data/arrival_alerts/alert_store.dart';
import '../domain/arrival/arrival_models.dart';
import '../domain/arrival_alerts/alert_tracker.dart';
import '../domain/arrival_alerts/arrival_alert.dart';
import '../platform/alert_runner.dart';
import '../platform/android_alert_watcher.dart';
import '../platform/ios_alert_scheduler.dart';
import '../routing/notification_route.dart';

final alertStoreProvider = Provider<AlertStore>((ref) => AlertStore());
final alertNotificationsProvider = Provider<AlertNotifications>((ref) => LocalAlertNotifications(onOpen: openAlertRoute));
final alertClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final alertRunnerProvider = Provider<AlertRunner>((ref) {
  final notifications = ref.watch(alertNotificationsProvider);
  if (defaultTargetPlatform == TargetPlatform.android) return AndroidAlertRunner(notifications, onOpen: openAlertRoute);
  return IosAlertRunner(AlertScheduler(
    notifications: notifications,
    clock: ref.watch(alertClockProvider),
    use24h: () => PlatformDispatcher.instance.alwaysUse24HourFormat,
  ));
});

enum SetAlertResult { set, permissionDenied }

/// The one active arrival alert (spec §2).
final arrivalAlertProvider =
    AsyncNotifierProvider<ArrivalAlertController, ArrivalAlert?>(ArrivalAlertController.new);

class ArrivalAlertController extends AsyncNotifier<ArrivalAlert?> {
  AlertStore get _store => ref.read(alertStoreProvider);
  AlertRunner get _runner => ref.read(alertRunnerProvider);
  DateTime _now() => ref.read(alertClockProvider)();

  @override
  Future<ArrivalAlert?> build() async {
    final sub = _runner.finished.listen((_) async {
      await _store.clear();
      state = const AsyncData(null);
    });
    final lifecycle = AppLifecycleListener(
      onPause: () => unawaited(onAppPaused()),
      onResume: () => unawaited(_reload()),
    );
    ref.onDispose(() {
      unawaited(sub.cancel());
      lifecycle.dispose();
    });
    final a = await _loadFresh();
    _ensureRunning(a);
    return a;
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
    final a = await _loadFresh();
    state = AsyncData(a);
    _ensureRunning(a);
  }

  /// A stored alert that has not fired needs its Android watcher: a reboot, force-stop or battery saver ends it.
  void _ensureRunning(ArrivalAlert? a) {
    if (a == null || a.firedAt != null || !_runner.watchesLive) return;
    unawaited(_runner.ensureRunning(a).catchError((Object _) {}));
  }

  Future<int> lastLead() => _store.lastLead();

  Future<bool> permissionGranted() => ref.read(alertNotificationsProvider).permissionGranted();

  Future<SetAlertResult> set(ArrivalRow row, {required String stopId, required String stopName, required int leadMinutes}) async {
    if (!await ref.read(alertNotificationsProvider).requestPermission()) return SetAlertResult.permissionDenied;
    final alert = ArrivalAlert.fromArrival(row, stopId: stopId, stopName: stopName, leadMinutes: leadMinutes, now: _now());
    await _store.write(alert);
    await _store.saveLead(leadMinutes);
    await _runner.start(alert);
    state = AsyncData(alert);
    return SetAlertResult.set;
  }

  Future<void> cancel() async {
    await _runner.stop();
    await _store.clear();
    state = const AsyncData(null);
  }

  /// The Board refreshed [stopId]. On iPhone a newer live prediction re-times the alert.
  void onBoardArrivals(String stopId, List<ArrivalRow> rows) {
    final a = state.value;
    if (a == null || a.stopId != stopId || _runner.watchesLive) return;
    for (final r in rows) {
      if (r.tripId != a.tripId || !r.isLive || r.predictedTime == null) continue;
      final now = _now();
      final retimed = a.copyWith(expectedAt: instantOfServiceTime(r.displayTime, now), live: true, lastSeenAt: now);
      if (retimed.expectedAt == a.expectedAt) return;
      unawaited(_deliverOnce(a, retimed, _runner.update));
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

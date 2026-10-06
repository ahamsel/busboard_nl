import 'dart:math' as math;

import '../data/arrival_alerts/alert_notifications.dart';
import '../domain/arrival_alerts/alert_copy.dart';
import '../domain/arrival_alerts/alert_tracker.dart';
import '../domain/arrival_alerts/arrival_alert.dart';
import 'alert_runner.dart';

/// iPhone: one notification at "expected − lead", re-timed whenever the app learns more (spec §3.1).
class AlertScheduler {
  AlertScheduler({required this.notifications, required this.clock, required this.use24h});

  final AlertNotifications notifications;
  final DateTime Function() clock;
  final bool Function() use24h;

  Future<void> scheduleFor(ArrivalAlert alert) async {
    final now = clock();
    final source = alert.live ? AlertSource.live : AlertSource.timetable;
    if (!now.isBefore(alert.alertAt)) {
      final minutes = math.max(0, alert.expectedAt.difference(now).inSeconds ~/ 60);
      await notifications.show(alertMessage(alert, source: source, minutesAway: minutes, use24h: use24h()));
      await notifications.cancelScheduled();
      return;
    }
    await notifications.schedule(
      alertMessage(alert,
          source: source,
          minutesAway: alert.leadMinutes,
          estimateFrom: alert.live ? alert.lastSeenAt ?? now : null,
          use24h: use24h()),
      alert.alertAt,
    );
  }

  Future<void> cancel() => notifications.cancelScheduled();
}

class IosAlertRunner implements AlertRunner {
  IosAlertRunner(this._scheduler);

  final AlertScheduler _scheduler;

  @override
  bool get watchesLive => false;

  @override
  Stream<void> get finished => const Stream.empty();

  @override
  Future<void> start(ArrivalAlert alert) => _scheduler.scheduleFor(alert);

  @override
  Future<void> update(ArrivalAlert alert) => _scheduler.scheduleFor(alert);

  @override
  Future<void> onBackground(ArrivalAlert alert) => _scheduler.scheduleFor(alert);

  /// The scheduled notification survives a reboot, and re-scheduling here could show a passed alert twice:
  /// the controller's fire-once bookkeeping owns that, so nothing to do.
  @override
  Future<void> ensureRunning(ArrivalAlert alert) async {}

  @override
  Future<void> stop() => _scheduler.cancel();
}

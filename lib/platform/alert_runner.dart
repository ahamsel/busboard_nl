// lib/platform/alert_runner.dart
import '../domain/arrival_alerts/arrival_alert.dart';

/// Runs the active arrival alert on this platform: the Android watcher or the iPhone scheduler.
abstract class AlertRunner {
  /// True on Android: the watcher owns the alert's timing and the store while it runs, so the app
  /// must not re-time or rewrite it.
  bool get watchesLive;

  /// Starts [alert], replacing any running one. The alert is already in the store.
  Future<void> start(ArrivalAlert alert);

  /// The app saw a newer prediction for [alert] (iPhone re-schedules; Android ignores it).
  Future<void> update(ArrivalAlert alert);

  /// The app is going to the background with [alert] set.
  Future<void> onBackground(ArrivalAlert alert);

  /// The app found [alert] stored and not yet fired, at launch or on coming back: make sure it is still
  /// running, since a reboot, force-stop or battery saver can end the Android watcher. Android only; the
  /// controller does not call it where [watchesLive] is false.
  Future<void> ensureRunning(ArrivalAlert alert);

  Future<void> stop();

  /// Fires when the platform side ended the alert itself (the bus was due, the cap, or Cancel on the notification).
  Stream<void> get finished;
}

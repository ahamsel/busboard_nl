// lib/platform/android_alert_watcher.dart
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../data/arrival_alerts/alert_notifications.dart';
import '../data/arrival_alerts/alert_store.dart';
import '../data/realtime/metrobus_mobile_api.dart';
import '../domain/arrival_alerts/alert_copy.dart';
import '../domain/arrival_alerts/alert_tracker.dart';
import '../domain/arrival_alerts/arrival_alert.dart';
import 'alert_runner.dart';

/// The backup alert comes this long after the live one would, so a live watcher always fires first (spec §3.3).
const backupGrace = Duration(minutes: 2);

const _serviceId = 4100;
const _cancelButton = 'cancel';
const _finishedEvent = 'arrival_alert.finished';

/// One watcher check, with every outside effect passed in so tests can run it.
class WatcherCore {
  WatcherCore({
    required this.store,
    required this.fetch,
    required this.notifications,
    required this.updateOngoing,
    required this.clock,
    required this.use24h,
  });

  final AlertStore store;
  final Future<MetrobusDeparturesResult> Function(String stopId) fetch;
  final AlertNotifications notifications;
  final Future<void> Function(String title, String text) updateOngoing;
  final DateTime Function() clock;
  final bool use24h;
  final AlertTracker _tracker = const AlertTracker();

  /// Returns false when the watcher should stop.
  Future<bool> check() async {
    final alert = await store.read();
    if (alert == null) return false;
    MetrobusDeparturesResult? result;
    try {
      result = await fetch(alert.stopId);
    } catch (_) {
      result = null;
    }
    final step = _tracker.step(alert, result, clock());
    // The rider may have cancelled or replaced the alert while the request was in flight.
    final current = await store.read();
    if (current == null || !current.isSameAlert(alert)) return false;
    if (step.fire) {
      await notifications.show(alertMessage(step.alert, source: step.source, minutesAway: step.minutesAway, use24h: use24h));
      await notifications.cancelScheduled();
    }
    if (step.finished) {
      await store.clear();
      await notifications.cancelScheduled();
      return false;
    }
    await store.write(step.alert);
    if (step.alert.firedAt == null) {
      await notifications.schedule(
        alertMessage(step.alert, source: AlertSource.timetable, minutesAway: step.alert.leadMinutes, use24h: use24h),
        step.alert.alertAt.add(backupGrace),
      );
    }
    await updateOngoing(ongoingTitle(step.alert), ongoingText(step));
    return true;
  }
}

@pragma('vm:entry-point')
void arrivalAlertWatcherStart() => FlutterForegroundTask.setTaskHandler(_ArrivalAlertTaskHandler());

class _ArrivalAlertTaskHandler extends TaskHandler {
  final _store = AlertStore();
  final _notifications = LocalAlertNotifications();
  final _api = MetrobusMobileApi();
  late final WatcherCore _core = WatcherCore(
    store: _store,
    fetch: (stopId) => _api.fetchDeparturesResult(stopId, forceRefresh: true),
    notifications: _notifications,
    updateOngoing: (title, text) =>
        FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text),
    clock: DateTime.now,
    use24h: PlatformDispatcher.instance.alwaysUse24HourFormat,
  );
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _notifications.init();
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_tick());

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await _core.check()) await _end();
    } finally {
      _busy = false;
    }
  }

  Future<void> _end() async {
    FlutterForegroundTask.sendDataToMain(_finishedEvent);
    await FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != _cancelButton) return;
    unawaited(() async {
      await _store.clear();
      await _notifications.cancelScheduled();
      await _end();
    }());
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Android: a `specialUse` foreground service that checks the stop every 30 s (spec §3.1).
class AndroidAlertRunner implements AlertRunner {
  AndroidAlertRunner(this._notifications) {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  final AlertNotifications _notifications;
  final _finished = StreamController<void>.broadcast();

  void _onTaskData(Object data) {
    if (data == _finishedEvent) _finished.add(null);
  }

  @override
  bool get watchesLive => true;

  @override
  Stream<void> get finished => _finished.stream;

  void _init() => FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'live_tracking',
          channelName: 'Live tracking',
          channelDescription: 'The countdown while an arrival alert runs.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(30000),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );

  @override
  Future<void> start(ArrivalAlert alert) async {
    _init();
    await _notifications.schedule(
      alertMessage(alert,
          source: AlertSource.timetable,
          minutesAway: alert.leadMinutes,
          use24h: PlatformDispatcher.instance.alwaysUse24HourFormat),
      alert.alertAt.add(backupGrace),
    );
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: ongoingTitle(alert),
      notificationText: 'Checking the live feed…',
      notificationIcon: const NotificationIcon(metaDataName: 'com.ahamsel.busboard_nl.NOTIFICATION_ICON'),
      notificationButtons: const [NotificationButton(id: _cancelButton, text: 'Cancel alert')],
      callback: arrivalAlertWatcherStart,
    );
  }

  @override
  Future<void> update(ArrivalAlert alert) async {}

  @override
  Future<void> onBackground(ArrivalAlert alert) async {}

  @override
  Future<void> stop() async {
    await _notifications.cancelScheduled();
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
  }
}

// lib/platform/android_alert_watcher.dart
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../data/arrival_alerts/alert_notifications.dart';
import '../data/arrival_alerts/alert_store.dart';
import '../data/realtime/metrobus_mobile_api.dart';
import '../data/realtime/timetrack_api.dart';
import '../domain/arrival_alerts/alert_copy.dart';
import '../domain/arrival_alerts/alert_tracker.dart';
import '../domain/arrival_alerts/arrival_alert.dart';
import '../domain/arrival_alerts/gtfs_rt_source.dart';
import 'alert_runner.dart';

/// The backup alert comes this long after the live one would, so a live watcher always fires first (spec §3.3).
const backupGrace = Duration(minutes: 2);

const _serviceId = 4100;
const _cancelButton = 'cancel';
const _finishedEvent = 'arrival_alert.finished';
const _maxFailures = 10;

/// What a check decided.
enum WatchOutcome {
  /// Keep checking.
  keepGoing,

  /// The alert is over (fired and due, capped, cancelled, or gone): the watcher should stop.
  finished,

  /// The store now holds a different alert; this check wrote nothing and the watcher keeps running for the new one.
  superseded,
}

/// When the backup alert should be scheduled for [alert], or null when none is needed: it has already fired,
/// or the time is not after [now] (the watcher's own check covers that case; scheduling would double-fire).
DateTime? backupTimeFor(ArrivalAlert alert, DateTime now) {
  if (alert.firedAt != null) return null;
  final at = alert.alertAt.add(backupGrace);
  return at.isAfter(now) ? at : null;
}

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
  /// The latest live data for the alert; a throw counts as a failed fetch.
  final Future<MetrobusDeparturesResult> Function(ArrivalAlert alert) fetch;
  final AlertNotifications notifications;
  final Future<void> Function(String title, String text) updateOngoing;
  final DateTime Function() clock;
  final bool use24h;
  final AlertTracker _tracker = const AlertTracker();

  Future<WatchOutcome> check() async {
    final alert = await store.read();
    if (alert == null) return WatchOutcome.finished;
    MetrobusDeparturesResult? result;
    try {
      result = await fetch(alert);
    } catch (_) {
      result = null;
    }
    final now = clock();
    final step = _tracker.step(alert, result, now);
    // The rider may have cancelled or replaced the alert while the request was in flight.
    final current = await store.read();
    if (current == null) return WatchOutcome.finished;
    if (!current.isSameAlert(alert)) return WatchOutcome.superseded;

    final message = step.fire
        ? alertMessage(
            step.alert,
            source: step.source,
            minutesAway: step.minutesAway,
            use24h: use24h,
          )
        : null;

    if (step.finished) {
      // Finish first so a failing notification cannot keep the watcher alive.
      await store.clear();
      await notifications.cancelScheduled();
      if (message != null) {
        try {
          await notifications.show(message);
        } catch (_) {}
      }
      return WatchOutcome.finished;
    }

    // Persist firedAt before showing, so a failed show never re-fires; the backup stays armed until the show succeeds.
    await store.write(step.alert);
    if (message != null) {
      try {
        await notifications.show(message);
        await notifications.cancelScheduled();
      } catch (_) {}
    }
    final backupAt = backupTimeFor(step.alert, now);
    if (backupAt != null) {
      await notifications.schedule(
        alertMessage(
          step.alert,
          source: AlertSource.timetable,
          minutesAway: step.alert.leadMinutes,
          use24h: use24h,
        ),
        backupAt,
      );
    }
    await updateOngoing(ongoingTitle(step.alert), ongoingText(step));
    return WatchOutcome.keepGoing;
  }
}

@pragma('vm:entry-point')
void arrivalAlertWatcherStart() =>
    FlutterForegroundTask.setTaskHandler(_ArrivalAlertTaskHandler());

class _ArrivalAlertTaskHandler extends TaskHandler {
  final _store = AlertStore();
  final _notifications = LocalAlertNotifications();
  // The open GTFS-RT feeds; Metrobus's stop endpoint answers 403 Forbidden (2026-10-05).
  final _api = TimeTrackApi();
  late final WatcherCore _core = WatcherCore(
    store: _store,
    fetch: (alert) async => liveResultForAlert(alert, await _api.fetchVehiclesResult(), DateTime.now()),
    notifications: _notifications,
    updateOngoing: (title, text) => FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    ),
    clock: DateTime.now,
    use24h: PlatformDispatcher.instance.alwaysUse24HourFormat,
  );
  Future<void>? _inFlight;
  bool _ended = false;
  int _failures = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _notifications.init();
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_tick());

  Future<void> _tick() {
    final running = _inFlight;
    if (running != null) return running;
    final tick = _runTick();
    _inFlight = tick;
    return tick.whenComplete(() => _inFlight = null);
  }

  Future<void> _runTick() async {
    try {
      final outcome = await _core.check();
      _failures = 0;
      if (outcome == WatchOutcome.finished) await _end();
    } catch (_) {
      // Keep trying for ~5 minutes of consecutive failures, then give up so the cap still holds.
      if (++_failures >= _maxFailures) {
        try {
          await _store.clear();
          await _notifications.cancelScheduled();
        } catch (_) {}
        await _end();
      }
    }
  }

  Future<void> _end() async {
    if (_ended) return;
    _ended = true;
    FlutterForegroundTask.sendDataToMain(_finishedEvent);
    await FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != _cancelButton) return;
    unawaited(() async {
      // Let a check that already passed its re-read finish first, so it cannot write the alert back.
      try {
        await _inFlight;
      } catch (_) {}
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

/// Android: a `specialUse` foreground service that checks the live feed every 30 s (spec §3.1).
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
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
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
    final backupAt = backupTimeFor(alert, DateTime.now());
    if (backupAt != null) {
      await _notifications.schedule(
        alertMessage(
          alert,
          source: AlertSource.timetable,
          minutesAway: alert.leadMinutes,
          use24h: PlatformDispatcher.instance.alwaysUse24HourFormat,
        ),
        backupAt,
      );
    }
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: ongoingTitle(alert),
      notificationText: 'Checking the live feed…',
      notificationIcon: const NotificationIcon(
        metaDataName: 'com.ahamsel.busboard_nl.NOTIFICATION_ICON',
      ),
      notificationButtons: const [
        NotificationButton(id: _cancelButton, text: 'Cancel alert'),
      ],
      callback: arrivalAlertWatcherStart,
    );
  }

  @override
  Future<void> update(ArrivalAlert alert) async {}

  @override
  Future<void> onBackground(ArrivalAlert alert) async {}

  @override
  Future<void> stop() async {
    // Stop the service first: a check still running could re-arm the backup after it is cancelled.
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    await _notifications.cancelScheduled();
  }
}

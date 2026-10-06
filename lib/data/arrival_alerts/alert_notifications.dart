import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/arrival_alerts/alert_copy.dart';

/// The notifications an arrival alert needs; a fake replaces it in tests.
abstract class AlertNotifications {
  Future<void> init();
  Future<bool> permissionGranted();

  /// Asks the phone for permission; true when granted.
  Future<bool> requestPermission();

  /// Shows the alert now.
  Future<void> show(AlertMessage m);

  /// Schedules the one pending alert (iPhone estimate, Android backup) at [at], replacing any earlier one.
  /// A time at or before now shows the alert at once.
  Future<void> schedule(AlertMessage m, DateTime at);
  Future<void> cancelScheduled();

  /// The route of the alert notification that launched the app, or null.
  Future<String?> launchRoute();
}

/// [AlertNotifications] on `flutter_local_notifications`. Android posts to the high-importance
/// "Arrival alerts" channel; the silent "Live tracking" channel belongs to the foreground service.
class LocalAlertNotifications implements AlertNotifications {
  LocalAlertNotifications({FlutterLocalNotificationsPlugin? plugin, this.onOpen})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Called with a tapped alert's route while the app runs (spec §2.2); [launchRoute] covers a cold start.
  final void Function(String? route)? onOpen;
  static const shownId = 4101;
  static const scheduledId = 4102;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'arrival_alerts',
      'Arrival alerts',
      channelDescription: 'A heads-up when your bus is a few minutes away.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: 'ic_notification',
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true, presentSound: true),
  );

  bool _ready = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => onOpen?.call(r.payload),
    );
    _ready = true;
  }

  @override
  Future<bool> permissionGranted() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.areNotificationsEnabled() ??
          false;
    }
    final options = await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true) ??
        false;
  }

  @override
  Future<void> show(AlertMessage m) async {
    await init();
    await _plugin.show(id: shownId, title: m.title, body: m.body, notificationDetails: _details, payload: m.route);
  }

  @override
  Future<void> schedule(AlertMessage m, DateTime at) async {
    // The plugin throws for a time that is not in the future.
    if (!at.isAfter(DateTime.now())) {
      await show(m);
      return;
    }
    await init();
    // A UTC instant needs no time-zone lookup: tz.UTC is built into the timezone package.
    await _plugin.zonedSchedule(
      id: scheduledId,
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: m.title,
      body: m.body,
      payload: m.route,
    );
  }

  @override
  Future<void> cancelScheduled() async {
    await init();
    await _plugin.cancel(id: scheduledId);
  }

  @override
  Future<String?> launchRoute() async {
    await init();
    final d = await _plugin.getNotificationAppLaunchDetails();
    return d != null && d.didNotificationLaunchApp ? d.notificationResponse?.payload : null;
  }
}

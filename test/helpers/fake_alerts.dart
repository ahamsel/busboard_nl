import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _QuietNotifications implements AlertNotifications {
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(AlertMessage m) async {}
  @override
  Future<void> schedule(AlertMessage m, DateTime at) async {}
  @override
  Future<void> cancelScheduled() async {}
}

class _QuietRunner implements AlertRunner {
  @override
  bool get watchesLive => true;
  @override
  Stream<void> get finished => const Stream.empty();
  @override
  Future<void> start(ArrivalAlert alert) async {}
  @override
  Future<void> update(ArrivalAlert alert) async {}
  @override
  Future<void> onBackground(ArrivalAlert alert) async {}
  @override
  Future<void> stop() async {}
}

/// Overrides that keep arrival alerts away from real plugins in screen tests.
final fakeAlertOverrides = [
  alertRunnerProvider.overrideWithValue(_QuietRunner()),
  alertNotificationsProvider.overrideWithValue(_QuietNotifications()),
];

/// Call in setUp: an in-memory store for SharedPreferencesAsync.
void useInMemoryAlertStore() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
  @override
  Future<String?> launchRoute() async => null;
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
  Future<void> ensureRunning(ArrivalAlert alert) async {}
  @override
  Future<void> stop() async {}
}

/// Overrides that keep arrival alerts away from real plugins in screen tests, with [runner] (default: a quiet one
/// that watches live) taking the alerts.
List<Override> fakeAlertOverridesWith([AlertRunner? runner]) => [
  alertRunnerProvider.overrideWithValue(runner ?? _QuietRunner()),
  alertNotificationsProvider.overrideWithValue(_QuietNotifications()),
];

/// Overrides that keep arrival alerts away from real plugins in screen tests.
final fakeAlertOverrides = fakeAlertOverridesWith();

/// Call in setUp: an in-memory store for SharedPreferencesAsync.
void useInMemoryAlertStore() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

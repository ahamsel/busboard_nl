import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'app_licenses.dart';
import 'ui/orientation_lock.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  // The Android arrival-alert watcher reports back to the app on this port.
  FlutterForegroundTask.initCommunicationPort();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  OrientationLock().attach();
  runApp(const ProviderScope(child: BusboardApp()));
}

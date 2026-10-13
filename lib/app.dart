import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'routing/notification_route.dart';
import 'routing/router.dart';
import 'ui/kit/bb_theme.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/arrival_alert_providers.dart';
import 'state/board_open_store.dart';
import 'state/providers.dart';

class BusboardApp extends ConsumerStatefulWidget {
  const BusboardApp({super.key});

  @override
  ConsumerState<BusboardApp> createState() => _BusboardAppState();
}

class _BusboardAppState extends ConsumerState<BusboardApp> {
  @override
  void initState() {
    super.initState();
    // Remove splash screen once the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Small delay to ensure smooth transition
      Future.delayed(const Duration(milliseconds: 100), () {
        FlutterNativeSplash.remove();
      });
    });
    unawaited(_startArrivalAlerts());
  }

  /// Loads the arrival alert at launch, which restarts a watcher the phone ended, and opens the Board of an
  /// alert notification that launched the app (spec §2.2).
  Future<void> _startArrivalAlerts() async {
    ref.read(arrivalAlertProvider);
    var opened = false;
    try {
      opened = openAlertRoute(await ref.read(alertNotificationsProvider).launchRoute());
    } catch (_) {
    } finally {
      // The home screen reopens the Board left open only now, and not at all after a launch link.
      final checked = ref.read(launchLinkCheckedProvider);
      if (!checked.isCompleted) checked.complete(opened);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: 'BusBoard NL',
      debugShowCheckedModeBanner: false,
      theme: BBTheme.light(),
      darkTheme: BBTheme.dark(),
      themeMode: settings.themeMode,
      scrollBehavior: const BBScrollBehavior(),
      routerConfig: appRouter,
    );
  }
}

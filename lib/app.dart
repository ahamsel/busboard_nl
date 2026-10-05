import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'routing/router.dart';
import 'ui/kit/bb_theme.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

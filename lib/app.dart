import 'package:flutter/material.dart';
import 'routing/router.dart';
import 'ui/theme/app_theme.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/providers.dart';

class BusboardApp extends ConsumerWidget {
  const BusboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: 'BusBoard NL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      routerConfig: appRouter,
    );
  }
}

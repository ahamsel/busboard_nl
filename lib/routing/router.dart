import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/home_sheet_provider.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/settings/settings_screen.dart';

/// The app's router.
final appRouter = buildAppRouter();

/// Opens [stopId]'s sheet on home: links and notifications for a stop land here (spec 2026-10-12 §3.6).
String _toStopSheet(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['stopId']!;
  final container = ProviderScope.containerOf(context, listen: false);
  // A redirect can run while the widget tree builds (the first route), when a provider may not change.
  Future.microtask(() => container.read(homeSheetProvider.notifier).open(StopSheet(id)));
  return '/';
}

/// A fresh router over the app's route tree (tests build their own so no state carries between them).
GoRouter buildAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            HomeScreen(pick: state.uri.queryParameters['pick']),
      ),
      GoRoute(path: '/stop/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/board/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/map', redirect: (_, _) => '/'),
      GoRoute(
        path: '/plan',
        redirect: (_, _) => '/',
        routes: [GoRoute(path: 'journey', redirect: (_, _) => '/')],
      ),
      GoRoute(
        path: '/alerts',
        builder: (context, state) => const AlertsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

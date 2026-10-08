import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/shell/app_shell.dart';
import '../ui/stop_picker/stop_picker_screen.dart';
import '../ui/board/arrival_board_screen.dart';
import '../ui/map/map_screen.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/settings/settings_screen.dart';
import '../ui/trip_planner/journey_detail_screen.dart';
import '../ui/trip_planner/plan_screen.dart';
import '../domain/trip_planner/journey.dart';

/// The app's router.
final appRouter = buildAppRouter();

/// A fresh router over the app's route tree (tests build their own so no state carries between them).
GoRouter buildAppRouter({String initialLocation = '/'}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // Branch 0: Board
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const StopPickerScreen(),
                routes: [
                  GoRoute(
                    path: 'board/:stopId',
                    builder: (context, state) {
                      final stopId = state.pathParameters['stopId']!;
                      return ArrivalBoardScreen(stopId: stopId);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 1: Map
          StatefulShellBranch(
            routes: [GoRoute(path: '/map', builder: (context, state) => const MapScreen())],
          ),
          // Branch 2: Service alerts
          StatefulShellBranch(
            routes: [GoRoute(path: '/alerts', builder: (context, state) => const AlertsScreen())],
          ),
          // Branch 3: Trip planner
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plan',
                builder: (context, state) => const PlanScreen(),
                routes: [
                  GoRoute(
                    path: 'journey',
                    // A deep link or a restored route carries no journey: back to the planner.
                    redirect: (context, state) => state.extra is Journey ? null : '/plan',
                    builder: (context, state) => JourneyDetailScreen(journey: state.extra! as Journey),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Settings pushes over the shell
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

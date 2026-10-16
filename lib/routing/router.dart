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

/// [child] as a page of Flutter's own [MaterialApp], so the theme's page transition (with its iOS edge swipe back)
/// runs. go_router 18 looks for `material_ui`'s MaterialApp, a different class from the one the app uses, and
/// without a page builder falls back to a page with no transition and no swipe back.
Page<void> _page(GoRouterState state, Widget child) => MaterialPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: <String, String>{...state.pathParameters, ...state.uri.queryParameters},
      restorationId: state.pageKey.value,
      child: child,
    );

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
                pageBuilder: (context, state) => _page(state, const StopPickerScreen()),
                routes: [
                  GoRoute(
                    path: 'board/:stopId',
                    pageBuilder: (context, state) {
                      final stopId = state.pathParameters['stopId']!;
                      return _page(state, ArrivalBoardScreen(stopId: stopId));
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 1: Map
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                pageBuilder: (context, state) => _page(state, MapScreen(pick: state.uri.queryParameters['pick'])),
              ),
            ],
          ),
          // Branch 2: Service alerts
          StatefulShellBranch(
            routes: [GoRoute(path: '/alerts', pageBuilder: (context, state) => _page(state, const AlertsScreen()))],
          ),
          // Branch 3: Trip planner
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plan',
                pageBuilder: (context, state) => _page(state, const PlanScreen()),
                routes: [
                  GoRoute(
                    path: 'journey',
                    // A deep link or a restored route carries no journey: back to the planner.
                    redirect: (context, state) => state.extra is Journey ? null : '/plan',
                    pageBuilder: (context, state) => _page(state, JourneyDetailScreen(journey: state.extra! as Journey)),
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
        pageBuilder: (context, state) => _page(state, const SettingsScreen()),
      ),
    ],
  );
}

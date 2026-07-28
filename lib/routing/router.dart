import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../ui/shell/app_shell.dart';
import '../ui/stop_picker/stop_picker_screen.dart';
import '../ui/board/arrival_board_screen.dart';
import '../ui/map/map_screen.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/settings/settings_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
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
          routes: [
            GoRoute(
              path: '/map',
              builder: (context, state) => const MapScreen(),
            ),
          ],
        ),
        // Branch 2: Service alerts
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/alerts',
              builder: (context, state) => const AlertsScreen(),
            ),
          ],
        ),
      ],
    ),
    // Settings pushes over the shell
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

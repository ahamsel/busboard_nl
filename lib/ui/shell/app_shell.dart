import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeAlertCount =
        ref
            .watch(serviceUpdatesProvider)
            .value
            ?.activeAlertsAt(DateTime.now())
            .length ??
        0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        backgroundColor: theme.scaffoldBackgroundColor,
        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.departure_board_outlined,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            selectedIcon: Icon(
              Icons.departure_board,
              color: theme.colorScheme.primary,
            ),
            label: 'Bus Board',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.map_outlined,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            selectedIcon: Icon(Icons.map, color: theme.colorScheme.primary),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: activeAlertCount,
              isLabelVisible: activeAlertCount > 0,
              child: Icon(
                Icons.campaign_outlined,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            selectedIcon: Badge.count(
              count: activeAlertCount,
              isLabelVisible: activeAlertCount > 0,
              child: Icon(Icons.campaign, color: theme.colorScheme.primary),
            ),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }
}

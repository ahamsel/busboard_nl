import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
        },
        backgroundColor: theme.scaffoldBackgroundColor,
        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.departure_board_outlined, color: Colors.white.withValues(alpha: 0.5)),
            selectedIcon: Icon(Icons.departure_board, color: theme.colorScheme.primary),
            label: 'Board',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined, color: Colors.white.withValues(alpha: 0.5)),
            selectedIcon: Icon(Icons.map, color: theme.colorScheme.primary),
            label: 'Map',
          ),
        ],
      ),
    );
  }
}

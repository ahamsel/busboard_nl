import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

/// Tab shell: branch content with the floating Harbour nav bar on top.
/// Board and Alerts scroll under the bar (they reserve
/// [BBNavBar.reservedHeight] at the end of their lists). The legacy map
/// (rebuilt in Phase 3) is laid out above the bar so its controls stay
/// reachable.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _mapBranch = 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAlertCount =
        ref.watch(serviceUpdatesProvider).value?.activeAlertsAt(DateTime.now()).length ?? 0;
    final index = navigationShell.currentIndex;

    return ColoredBox(
      color: context.bb.colors.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: index == _mapBranch ? BBNavBar.reservedHeight(context) : 0),
              child: navigationShell,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BBNavBar(
              items: [
                const BBNavItem(label: 'Board', icon: BBIcons.board, activeIcon: BBIcons.boardFill),
                const BBNavItem(label: 'Map', icon: BBIcons.map, activeIcon: BBIcons.mapFill),
                BBNavItem(
                  label: 'Alerts',
                  icon: BBIcons.alerts,
                  activeIcon: BBIcons.alertsFill,
                  badgeCount: activeAlertCount,
                ),
              ],
              currentIndex: index,
              onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == index),
            ),
          ),
        ],
      ),
    );
  }
}

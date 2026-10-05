import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

/// Tab shell: branch content with the floating Harbour nav bar on top.
/// Every branch runs under the bar. Board and Alerts reserve
/// [BBNavBar.reservedHeight] at the end of their lists; the map lays out its
/// own sheet above the bar (spec §2.4).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAlertCount =
        ref.watch(serviceUpdatesProvider).value?.activeAlertsAt(DateTime.now()).length ?? 0;
    final index = navigationShell.currentIndex;

    return BBNavBarScope(
      child: ColoredBox(
        color: context.bb.colors.bg,
        child: Stack(
          children: [
            Positioned.fill(child: navigationShell),
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
      ),
    );
  }
}

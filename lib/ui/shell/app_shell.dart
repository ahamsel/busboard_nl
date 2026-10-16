import 'dart:async';

import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

/// Tab shell: branch content with the floating Harbour nav bar on top.
/// Every branch runs under the bar. Board and Alerts reserve
/// [BBNavBar.reservedHeight] at the end of their lists; the map lays out its
/// own sheet above the bar (spec §2.4).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _mapBranch = 1;

  /// The tabs' names, as the bar shows them and as an action's switch announces them.
  static const _tabNames = ['Board', 'Map', 'Alerts', 'Plan'];

  /// The tab bar asked for the branch now coming in: the rider chose it, so it is not announced.
  bool _barSwitch = false;

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = widget.navigationShell.currentIndex;
    final moved = index != oldWidget.navigationShell.currentIndex;
    final byBar = _barSwitch;
    _barSwitch = false;
    // An action took the rider to another tab (Follow on the Board opens the Map): the screen they were on is taken
    // away from them, so a screen reader says where they are now.
    if (moved && !byBar && index < _tabNames.length) {
      unawaited(
        SemanticsService.sendAnnouncement(View.of(context), '${_tabNames[index]} tab', Directionality.of(context)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final activeAlertCount = ref.watch(serviceUpdatesProvider).value?.activeAlertsAt(DateTime.now()).length ?? 0;
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
                  BBNavItem(label: _tabNames[0], icon: BBIcons.board, activeIcon: BBIcons.boardFill),
                  BBNavItem(label: _tabNames[1], icon: BBIcons.map, activeIcon: BBIcons.mapFill),
                  BBNavItem(
                    label: _tabNames[2],
                    icon: BBIcons.alerts,
                    activeIcon: BBIcons.alertsFill,
                    badgeCount: activeAlertCount,
                  ),
                  BBNavItem(label: _tabNames[3], icon: BBIcons.plan, activeIcon: BBIcons.planFill),
                ],
                currentIndex: index,
                // The Map tab always opens the plain map: a pick on the map that was left unfinished is over.
                onSelect: (i) {
                  _barSwitch = i != index;
                  navigationShell.goBranch(i, initialLocation: i == index || i == _mapBranch);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

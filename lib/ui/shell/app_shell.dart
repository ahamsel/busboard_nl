import 'dart:async';

import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../kit/kit.dart';

/// Tab shell: the two tabs, Board and Map, with the floating Harbour nav bar on top.
/// Every branch runs under the bar. The Board's pages reserve
/// [BBNavBar.reservedHeight] at the end of their lists; the map lays out its
/// own sheet above the bar (spec §2.4). The trip planner, the service alerts
/// and Settings are pages pushed over the shell, from the buttons at the top
/// right of both tabs (`TopActions`).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _mapBranch = 1;

  /// The tabs' names, as the bar shows them and as an action's switch announces them.
  static const _tabNames = ['Board', 'Map'];

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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/home_tab_provider.dart';
import '../../state/map_request_provider.dart';
import '../board/board_tab.dart';
import '../kit/kit.dart';
import 'home_screen.dart';

/// The home (spec 2026-10-15 §2): two tabs, Board and Map, over a bottom tab bar. Both stay mounted, so a switch
/// keeps the map, its camera and follow, and the Board's scroll, as they were; the tab not showing is offstage, its
/// tickers off. The Board cross-fades in over the map, or out to show it, over [BBMotion.standard] (at once under
/// Reduce Motion); the map itself never fades, as a platform view under an opacity layer can flicker. Both tabs run to
/// the bottom edge, under the floating tab bar, and see its top edge as their bottom padding: the map's sheet measures
/// its stops from there, and the Board's list leaves room to scroll its end out from behind it.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  static const boardTabKey = ValueKey('home-tab-board');
  static const mapTabKey = ValueKey('home-tab-map');
  static const boardLayerKey = ValueKey('home-layer-board');
  static const mapLayerKey = ValueKey('home-layer-map');

  static const _tabs = [
    BBTab(label: 'Board', icon: BBIcons.board, activeIcon: BBIcons.boardFill, key: boardTabKey),
    BBTab(label: 'Map', icon: BBIcons.map, activeIcon: BBIcons.mapFill, key: mapTabKey),
  ];

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with SingleTickerProviderStateMixin {
  /// 1 with the Board showing, 0 with the map; in between while they cross-fade.
  late final AnimationController _board = AnimationController(vsync: this, duration: BBMotion.standard);

  @override
  void initState() {
    super.initState();
    final tab = ref.read(homeTabProvider);
    if (tab != null) _board.value = tab == HomeTab.board ? 1 : 0;
    // The first tab (read from the phone) shows at once; a switch after that cross-fades.
    ref.listenManual<HomeTab?>(homeTabProvider, (previous, next) {
      if (next == null || !mounted) return;
      final target = next == HomeTab.board ? 1.0 : 0.0;
      final duration = BBMotion.of(context, BBMotion.standard);
      if (previous == null || duration == Duration.zero) {
        _board.value = target;
      } else {
        _board.animateTo(target, duration: duration, curve: BBMotion.curve);
      }
    });
    // What only the map can show switches to it (spec 2026-10-15 §2.3), from the Board or anywhere else: a bus
    // followed, a trip's options or steps (Where to? or Plan a trip from here on the Board), and choosing on the map.
    // Each of those asks at the action, so asking again for what is already set still switches.
    // The switch is said to screen readers, as the Board they were on is taken away from them (final review M4).
    ref.listenManual<int>(mapRequestProvider, (_, _) {
      final tabs = ref.read(homeTabProvider.notifier);
      final moved = ref.read(homeTabProvider) != HomeTab.map;
      tabs.select(HomeTab.map);
      if (moved && mounted) {
        unawaited(SemanticsService.sendAnnouncement(View.of(context), 'Map tab', Directionality.of(context)));
      }
    });
  }

  @override
  void dispose() {
    _board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final tab = ref.watch(homeTabProvider);
    // The tab used last is still being read (a frame or two at launch).
    if (tab == null) return ColoredBox(color: bb.colors.bg);
    final layers = Stack(
      fit: StackFit.expand,
      children: [
        _TabLayer(
          key: HomeShell.mapLayerKey,
          board: _board,
          isBoard: false,
          active: tab == HomeTab.map,
          child: HomeScreen(active: tab == HomeTab.map),
        ),
        _TabLayer(
          key: HomeShell.boardLayerKey,
          board: _board,
          isBoard: true,
          active: tab == HomeTab.board,
          // Its own page: opaque bg over the map, status-bar icons for the theme, clear of a side notch.
          child: const BBScaffold(safeTop: false, body: BoardTab()),
        ),
      ],
    );
    // No page scaffold around both: the map runs under the status bar and handles the side insets itself (the tablet
    // panel clears a notch); the Board brings its own.
    return ColoredBox(
      color: bb.colors.bg,
      child: BBTabBarLayout(
        // Both tabs run to the bottom edge, behind the floating tab bar, and take its space (its top edge, safe area
        // included, which grows with the text) as their bottom padding: the map's sheet and controls sit above it, the
        // Board's list scrolls out from behind it. A toast shown from either tab clears it too, so it never covers the
        // tabs or takes their taps (final review M2).
        body: (context, inset) {
          final media = MediaQuery.of(context);
          return BBToastInset(
            bottom: inset,
            child: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: inset),
                viewPadding: media.viewPadding.copyWith(bottom: math.max(media.viewPadding.bottom, inset)),
              ),
              child: layers,
            ),
          );
        },
        bar: BBTabBar(
          tabs: HomeShell._tabs,
          index: tab.index,
          onSelect: (i) => ref.read(homeTabProvider.notifier).select(HomeTab.values[i]),
        ),
      ),
    );
  }
}

/// One tab's layer. Offstage once fully hidden (not painted, not hit, not read, and skipped by finders); while it
/// is not the active tab it takes no touches or focus, says nothing to screen readers and runs no tickers. The Board's layer
/// fades with [board]; the map's stays opaque under it.
class _TabLayer extends AnimatedWidget {
  const _TabLayer({
    super.key,
    required Animation<double> board,
    required this.isBoard,
    required this.active,
    required this.child,
  }) : super(listenable: board);

  final bool isBoard;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final board = (listenable as Animation<double>).value;
    final visible = active || (isBoard ? board > 0 : board < 1);
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          child: ExcludeSemantics(
            excluding: !active,
            // Nor a keyboard's or a switch's focus: Tab never walks into the tab behind.
            child: ExcludeFocus(
              excluding: !active,
              child: Opacity(opacity: isBoard ? board : 1, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

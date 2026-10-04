import 'package:flutter/material.dart';

import 'tokens.dart';

/// App ThemeData built from [BBTokens]. Material stays as plumbing: ripples,
/// tints and platform-specific transitions are switched off. The ColorScheme
/// and TextTheme are mapped from tokens so not-yet-migrated screens pick up
/// the Harbour colours and Figtree until Phase 2 replaces them.
abstract final class BBTheme {
  static ThemeData light() => _build(BBTokens.light);
  static ThemeData dark() => _build(BBTokens.dark);

  static ThemeData _build(BBTokens t) {
    final c = t.colors;
    final base = ThemeData(brightness: t.brightness, useMaterial3: true);
    final scheme = ColorScheme(
      brightness: t.brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      secondary: c.live,
      onSecondary: c.onBrand,
      error: c.dangerInk,
      onError: c.surface,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      surfaceContainerHighest: c.surfaceSunken,
      outline: c.line,
      outlineVariant: c.line,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      fontFamily: BBText.family,
      textTheme: base.textTheme.apply(
        fontFamily: BBText.family,
        bodyColor: c.ink,
        displayColor: c.ink,
      ),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: BBPageTransitionsBuilder(),
          TargetPlatform.iOS: BBPageTransitionsBuilder(),
        },
      ),
      // Legacy-screen defaults until Phase 2 removes AppBar/Card usage.
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: t.text.headline,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BBRadius.card)),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1),
      extensions: [t],
    );
  }
}

/// One scroll feel on both platforms: bounce, no glow/stretch, no scrollbar.
class BBScrollBehavior extends ScrollBehavior {
  const BBScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// One page transition on both platforms: fade + 4% slide-up. On iOS an
/// edge-swipe-back gesture is added; Android's system back already pops.
class BBPageTransitionsBuilder extends PageTransitionsBuilder {
  const BBPageTransitionsBuilder();

  @override
  Duration get transitionDuration => BBMotion.standard;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: BBMotion.curve, reverseCurve: Curves.easeInCubic);
    Widget page = FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      page = BBEdgeSwipeBack(canPop: () => route.popGestureEnabled, child: page);
    }
    return page;
  }
}

/// Drag from the left edge to go back. The page follows the finger. Releasing
/// past a third of the width (or flinging) pops; otherwise it springs back.
class BBEdgeSwipeBack extends StatefulWidget {
  const BBEdgeSwipeBack({super.key, required this.canPop, required this.child, this.edgeWidth = 20});

  final bool Function() canPop;
  final Widget child;
  final double edgeWidth;

  @override
  State<BBEdgeSwipeBack> createState() => _BBEdgeSwipeBackState();
}

class _BBEdgeSwipeBackState extends State<BBEdgeSwipeBack> with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(vsync: this, duration: BBMotion.standard)
    ..addListener(() => setState(() => _dx = _settleFrom * (1 - Curves.easeOut.transform(_settle.value))));
  double _dx = 0;
  double _settleFrom = 0;
  bool _tracking = false;

  void _start(DragStartDetails _) {
    _tracking = widget.canPop();
    if (_tracking) _settle.stop();
  }

  void _update(DragUpdateDetails d) {
    if (!_tracking) return;
    final width = context.size?.width ?? 0;
    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, width));
  }

  void _end(DragEndDetails d) {
    if (!_tracking) return;
    _tracking = false;
    final width = context.size?.width ?? 1;
    final velocity = d.primaryVelocity ?? 0;
    if (_dx > width / 3 || velocity > 600) {
      Navigator.of(context).maybePop();
    } else {
      _springBack();
    }
  }

  void _springBack() {
    _tracking = false;
    _settleFrom = _dx;
    _settle.forward(from: 0);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: widget.edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _start,
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: _end,
            onHorizontalDragCancel: () {
              if (_tracking) _springBack();
            },
          ),
        ),
      ],
    );
  }
}

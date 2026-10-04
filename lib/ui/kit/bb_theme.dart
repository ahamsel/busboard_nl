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
      secondary: c.liveInk,
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

    OutlineInputBorder inputBorder(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(BBRadius.button),
          borderSide: BorderSide(color: color, width: width),
        );
    final buttonStyle = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(c.brand),
      foregroundColor: WidgetStatePropertyAll(c.onBrand),
      elevation: const WidgetStatePropertyAll(0),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(BBRadius.button)),
      ),
      textStyle: WidgetStatePropertyAll(t.text.label.copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
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
      // Legacy-screen defaults until Phase 2: filled, rounded text fields.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: inputBorder(c.line, 1),
        enabledBorder: inputBorder(c.line, 1),
        focusedBorder: inputBorder(c.brand, 2),
        hintStyle: t.text.body.copyWith(color: c.muted),
      ),
      // Legacy-screen defaults until Phase 2: solid brand buttons.
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
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
    // Reduce motion: no fade or slide, the page is simply there. (The route's
    // own animation still runs, since transitionDuration has no context, but
    // nothing visible is tied to it.)
    Widget page = child;
    if (MediaQuery.maybeDisableAnimationsOf(context) != true) {
      final curved = animation.drive(CurveTween(curve: BBMotion.curve));
      page = FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: curved.drive(Tween(begin: const Offset(0, 0.04), end: Offset.zero)),
          child: child,
        ),
      );
    }
    // ModalRoute hands us a ProxyAnimation around the route's controller (and
    // briefly a constant one while offstage), so the gesture resolves the real
    // AnimationController lazily when a drag starts.
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      page = BBEdgeSwipeBack(
        canPop: () => route.popGestureEnabled,
        animation: animation,
        child: page,
      );
    }
    return page;
  }
}

/// Drag from the left edge to go back. The swipe drives the route's own
/// route's [AnimationController] (so the previous page is painted underneath,
/// as with Cupertino's back gesture) and the page follows the finger. Releasing past a
/// third of the width (or flinging) pops; otherwise it springs back.
class BBEdgeSwipeBack extends StatefulWidget {
  const BBEdgeSwipeBack({
    super.key,
    required this.canPop,
    required this.animation,
    required this.child,
    this.edgeWidth = 20,
  });

  final bool Function() canPop;

  /// The route's transition animation (1 = page fully shown, 0 = dismissed).
  /// It may be a [ProxyAnimation] chain; the swipe only engages if that chain
  /// ends in an [AnimationController].
  final Animation<double> animation;
  final Widget child;
  final double edgeWidth;

  @override
  State<BBEdgeSwipeBack> createState() => _BBEdgeSwipeBackState();
}

class _BBEdgeSwipeBackState extends State<BBEdgeSwipeBack> {
  // True from drag start until the controller settles back to fully shown (or
  // the route is gone). While true the page is offset by the controller.
  bool _active = false;
  bool _tracking = false;
  NavigatorState? _navigator;
  AnimationController? _controller;

  static AnimationController? _unwrap(Animation<double> animation) {
    var a = animation;
    while (a is ProxyAnimation) {
      final parent = a.parent;
      if (parent == null) return null;
      a = parent;
    }
    return a is AnimationController ? a : null;
  }

  void _start(DragStartDetails _) {
    _controller = _unwrap(widget.animation);
    _tracking = _controller != null && widget.canPop();
    if (!_tracking) return;
    _navigator = Navigator.of(context)..didStartUserGesture();
    _controller!.stop();
    setState(() => _active = true);
  }

  void _update(DragUpdateDetails d) {
    if (!_tracking) return;
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    _controller!.value -= d.delta.dx / width;
  }

  void _end(DragEndDetails d) {
    if (!_tracking) return;
    final velocity = d.primaryVelocity ?? 0;
    final dismissed = 1 - _controller!.value;
    _finish(pop: dismissed > 1 / 3 || velocity > 600);
  }

  // Mirrors Cupertino's back-gesture controller: pop through the navigator
  // (the reverse animation continues from the current value) or animate back to
  // fully shown, and keep userGestureInProgress true until the controller
  // settles so the transition doesn't change mid-flight.
  void _finish({required bool pop}) {
    _tracking = false;
    final controller = _controller!;
    final navigator = _navigator!;
    _navigator = null;
    const curve = Curves.easeOut;
    if (pop) {
      navigator.pop();
    } else {
      controller.animateTo(1.0, duration: BBMotion.standard, curve: curve);
    }
    if (controller.isAnimating) {
      late AnimationStatusListener listener;
      listener = (status) {
        if (status != AnimationStatus.completed && status != AnimationStatus.dismissed) return;
        controller.removeStatusListener(listener);
        navigator.didStopUserGesture();
        if (mounted && status == AnimationStatus.completed) setState(() => _active = false);
      };
      controller.addStatusListener(listener);
    } else {
      navigator.didStopUserGesture();
      if (mounted && !pop) setState(() => _active = false);
    }
  }

  void _cancel() {
    if (_tracking) _finish(pop: false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: widget.animation,
            child: widget.child,
            builder: (context, child) {
              final dx = _active ? (1 - widget.animation.value) * constraints.maxWidth : 0.0;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
          ),
        ),
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
            onHorizontalDragCancel: _cancel,
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'bb_card.dart';
import 'tokens.dart';

enum BBSheetDetent { peek, half, full }

/// Drives a [BBSheet]: its size (it is a [DraggableScrollableController]) and
/// detent moves that honour reduce motion.
class BBSheetController extends DraggableScrollableController {
  _BBSheetState? _sheet;

  /// Where the last move asked by code ([animateTo], [jumpTo]) takes the sheet; null once the rider drags it.
  double? _target;

  @override
  Future<void> animateTo(double size, {required Duration duration, required Curve curve}) {
    _target = size;
    return super.animateTo(size, duration: duration, curve: curve);
  }

  @override
  void jumpTo(double size) {
    _target = size;
    super.jumpTo(size);
  }

  /// Springs to [detent] (spec §3.2: the emphasis spring, slight overshoot; 1 ms with reduce motion). No-op when detached.
  ///
  /// Don't await this from tests or from code that can unmount the sheet: the
  /// future may never complete if the sheet goes away mid-animation. Use
  /// `unawaited(...)`.
  Future<void> animateToDetent(BBSheetDetent detent) async {
    final sheet = _sheet;
    if (sheet == null || !isAttached) return;
    // A move of its own: it cuts short any nudge, whose quiet would otherwise outlive it.
    sheet._endQuiet();
    await animateTo(sheet._fractionOf(detent), duration: sheet._snapDuration, curve: BBMotion.emphasisCurve);
  }

  /// Back to peek, e.g. when the map behind the sheet is tapped.
  ///
  /// Same caveat as [animateToDetent]: don't await it from tests or from code
  /// that can unmount the sheet; use `unawaited(...)`.
  Future<void> collapse() => animateToDetent(BBSheetDetent.peek);

  /// "There is more above": lifts the sheet [lift] logical pixels and settles it back where it was, with no haptic
  /// tick (spec 2026-10-14 §3.6). Does nothing under reduce motion, or when detached.
  ///
  /// Same caveat as [animateToDetent]: don't await it from tests; use `unawaited(...)`.
  Future<void> nudge(double lift) async {
    final sheet = _sheet;
    if (sheet == null || !isAttached || sheet._reduced) return;
    final rest = size;
    final atPeek = (rest - sheet.widget.peekFraction).abs() < _BBSheetState._tolerance;
    final up = math.min(rest + pixelsToSize(lift), sheet.widget.fullFraction);
    final token = sheet._beginQuiet();
    try {
      await animateTo(up, duration: BBMotion.standard, curve: BBMotion.curve);
      if (!isAttached) return;
      // From the peek, back to the peek as it is now: the content above it may have shrunk meanwhile.
      await animateTo(atPeek ? sheet.widget.peekFraction : rest, duration: BBMotion.emphasis, curve: BBMotion.curve);
    } finally {
      // Only this nudge's own quiet: a newer one may have begun since.
      if (sheet._quietToken == token) sheet._endQuiet();
    }
  }
}

/// Floating card sheet with three detents (peek / half / full): inset by
/// [sideMargin], rounded on every corner, lifted above [bottomInset] (the nav
/// bar on the map), with an optional [header] pinned above the scrolling
/// [slivers]. One haptic tick when it settles on a detent. The grab handle is
/// an adjustable control for screen readers (Expand / Collapse / Close), or,
/// with [handleButton], a button that moves one stop ("Show more" / "Show less").
/// Place it in a Stack over the content.
class BBSheet extends StatefulWidget {
  const BBSheet({
    super.key,
    required this.slivers,
    this.header,
    required this.peekFraction,
    this.halfFraction = 0.5,
    this.fullFraction = 0.9,
    this.initialFraction,
    this.controller,
    this.bottomInset = 0,
    this.dismissible = false,
    this.onDismiss,
    this.semanticLabel = 'Sheet',
    this.fadeUnderHeader = false,
    this.handleButton = false,
  })  : assert(
          peekFraction > 0 && peekFraction < halfFraction && halfFraction < fullFraction && fullFraction <= 1,
          'BBSheet fractions must satisfy 0 < peek < half < full <= 1',
        ),
        assert(!dismissible || onDismiss != null, 'A dismissible BBSheet needs onDismiss');

  final List<Widget> slivers;
  final Widget? header;
  final double peekFraction;
  final double halfFraction;
  final double fullFraction;
  final double? initialFraction;
  final BBSheetController? controller;
  final double bottomInset;
  /// Whether the sheet can be swiped (or closed by screen reader) down to
  /// nothing. A dismissible sheet needs [onDismiss].
  final bool dismissible;

  /// Called once when a dismissible sheet closes. The parent should unmount, or
  /// re-key, the sheet here: a dismissed sheet stays mounted at extent 0.
  final VoidCallback? onDismiss;
  final String semanticLabel;

  /// Home: the top of the list fades under the pinned header once it scrolls (spec §5).
  final bool fadeUnderHeader;

  /// Home (spec 2026-10-14 §3.6): the grab handle is a button, "Show more" at peek and "Show less" above it, and a
  /// tap moves one stop: peek to half, half to peek, full to half. It takes [handleButtonExtent] above the header, but
  /// its target is [handleButtonTarget] tall: it reaches down over the header's top, where the header's own controls
  /// keep their taps (final review M9).
  final bool handleButton;

  static const double sideMargin = 8;

  /// The grab handle's height above the header: 8 + 4 + 8, or [handleButtonExtent] when it is a button.
  static const double handleExtent = 20;
  static const double handleButtonExtent = 24;
  static const double handleButtonTarget = 44;
  static const cardKey = ValueKey('bb-sheet-card');
  static const handleKey = ValueKey('bb-sheet-handle');
  static const headerKey = ValueKey('bb-sheet-header');
  static const fadeKey = ValueKey('bb-sheet-fade');
  static const topFadeKey = ValueKey('bb-sheet-top-fade');

  /// The list fades to clear over its last [fadeExtent] while more is below (spec §5).
  static const double fadeExtent = 24;
  static const double topFadeExtent = 16;

  /// The bottom fade's gradient stops for a list [height] tall: opaque, then clear over the last
  /// [fadeExtent]. Off (or too short to fade), it stays opaque.
  static List<double> fadeStops(double height, {required bool on}) =>
      !on || height <= fadeExtent ? const [0, 1, 1] : [0, 1 - fadeExtent / height, 1];

  @override
  State<BBSheet> createState() => _BBSheetState();
}

class _BBSheetState extends State<BBSheet> {
  static const _tolerance = 0.004;
  static const _settleDelay = Duration(milliseconds: 80);

  late BBSheetController _controller = widget.controller ?? BBSheetController();
  // DraggableScrollableSheet compares snapSizes by identity and re-snaps (which
  // drops a live drag) when it changes, so the list must keep one identity
  // across rebuilds.
  late List<double> _snapSizes = _computeSnapSizes();
  late double? _lastDetent = widget.initialFraction ?? widget.peekFraction;
  late double _extent = widget.initialFraction ?? widget.peekFraction;
  Timer? _settleTimer;
  bool _dismissed = false;
  bool _scrolled = false;
  bool _moreBelow = false;
  Duration _snapDuration = BBMotion.emphasis;
  bool _reduced = false;

  /// While [BBSheetController.nudge] runs: leaving and coming back to a detent is not a new settle (no tick). A drag
  /// or another move cuts the nudge short, and its animation then never completes (a stopped ticker's future does
  /// not), so they end the quiet themselves (final review M3).
  bool _quiet = false;

  /// Counts nudges, so a nudge ends only its own quiet.
  int _quietToken = 0;

  int _beginQuiet() {
    _quiet = true;
    return ++_quietToken;
  }

  void _endQuiet() {
    _quiet = false;
    _quietToken++;
  }

  @override
  void initState() {
    super.initState();
    _controller._sheet = this;
  }

  List<double> _computeSnapSizes() =>
      widget.dismissible ? [widget.peekFraction, widget.halfFraction] : [widget.halfFraction];

  @override
  void didUpdateWidget(BBSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (identical(_controller._sheet, this)) _controller._sheet = null;
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? BBSheetController();
      _controller._sheet = this;
    }
    if (widget.dismissible != oldWidget.dismissible ||
        widget.peekFraction != oldWidget.peekFraction ||
        widget.halfFraction != oldWidget.halfFraction) {
      _snapSizes = _computeSnapSizes();
    }
    if (widget.peekFraction != oldWidget.peekFraction) _followPeek(oldWidget.peekFraction);
  }

  /// The peek moved (the header grew or shrank). A sheet resting at the old peek moves to the new one. Flutter's
  /// sheet does that by itself only until it is first moved by code: after that it keeps its size, clamped, so a
  /// smaller peek would leave it resting taller than its content (final review I1). Not a sheet on its way somewhere
  /// else (a card opening to half), nor one the rider has moved off its peek.
  void _followPeek(double oldPeek) {
    final newPeek = widget.peekFraction;
    if (_lastDetent == oldPeek) _lastDetent = newPeek; // the same rest, moved: no tick
    // After the frame: the inner sheet takes its new bounds in this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isAttached || widget.peekFraction != newPeek) return;
      final size = _controller.size;
      final target = _controller._target;
      final resting = (size - oldPeek).abs() < _tolerance && (target == null || (target - oldPeek).abs() < _tolerance);
      if (resting && (size - newPeek).abs() >= _tolerance) _controller.jumpTo(newPeek);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The sheet API rejects Duration.zero, so "reduce motion" uses 1 ms.
    final d = BBMotion.of(context, BBMotion.emphasis);
    _snapDuration = d == Duration.zero ? const Duration(milliseconds: 1) : d;
    _reduced = BBMotion.reduced(context);
  }

  double _fractionOf(BBSheetDetent detent) => switch (detent) {
        BBSheetDetent.peek => widget.peekFraction,
        BBSheetDetent.half => widget.halfFraction,
        BBSheetDetent.full => widget.fullFraction,
      };

  BBSheetDetent get _nearest {
    var best = BBSheetDetent.peek;
    for (final d in BBSheetDetent.values) {
      if ((_fractionOf(d) - _extent).abs() < (_fractionOf(best) - _extent).abs()) best = d;
    }
    return best;
  }

  double? _detentNear(double extent) {
    for (final detent in [widget.peekFraction, widget.halfFraction, widget.fullFraction]) {
      if ((extent - detent).abs() < _tolerance) return detent;
    }
    return null;
  }

  // Notifications fire on every size update, so a detent is only "settled"
  // once the extent has stayed on it for a short debounce.
  bool _onExtent(DraggableScrollableNotification n) {
    final nearestBefore = _nearest;
    _extent = n.extent;
    // Rebuild the handle's semantics (value and actions) after the frame:
    // notifications can arrive mid-layout, where setState is not allowed.
    if (_nearest != nearestBefore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    _settleTimer?.cancel();
    // Re-arm dismissal once the sheet has been reopened.
    if (n.extent >= _tolerance) _dismissed = false;
    if (widget.dismissible && n.extent < _tolerance) {
      _settleTimer = Timer(_settleDelay, _dismiss);
      return false;
    }
    final detent = _detentNear(n.extent);
    if (detent == null) {
      if (!_quiet) _lastDetent = null;
      return false;
    }
    _settleTimer = Timer(_settleDelay, () {
      if (_detentNear(_extent) == detent && _lastDetent != detent) {
        _lastDetent = detent;
        HapticFeedback.selectionClick();
      }
    });
    return false;
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    widget.onDismiss?.call();
  }

  void _go(BBSheetDetent detent) => unawaited(_controller.animateToDetent(detent));

  @override
  void dispose() {
    _settleTimer?.cancel();
    if (identical(_controller._sheet, this)) _controller._sheet = null;
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  static String _valueOf(BBSheetDetent d) => switch (d) {
        BBSheetDetent.peek => 'Collapsed',
        BBSheetDetent.half => 'Half open',
        BBSheetDetent.full => 'Expanded',
      };

  Widget _handle(BuildContext context) {
    final bb = context.bb;
    final at = _nearest;
    final bar = Container(
      width: 34,
      height: 4,
      decoration: BoxDecoration(color: bb.colors.handle, borderRadius: BorderRadius.circular(2)),
    );
    if (widget.handleButton) return _handleButton(at, bar);
    final up = switch (at) {
      BBSheetDetent.peek => BBSheetDetent.half,
      _ => BBSheetDetent.full,
    };
    final down = switch (at) {
      BBSheetDetent.full => BBSheetDetent.half,
      _ => BBSheetDetent.peek,
    };
    return Semantics(
      key: BBSheet.handleKey,
      container: true,
      label: widget.semanticLabel,
      value: _valueOf(at),
      // A semantics node with an increase/decrease action must also name the
      // value each one leads to.
      increasedValue: at == BBSheetDetent.full ? null : _valueOf(up),
      decreasedValue: at == BBSheetDetent.peek
          ? (widget.dismissible ? 'Closed' : null)
          : _valueOf(down),
      onIncrease: at == BBSheetDetent.full ? null : () => _go(up),
      onDecrease: at == BBSheetDetent.peek ? (widget.dismissible ? _dismiss : null) : () => _go(down),
      customSemanticsActions: {
        if (at != BBSheetDetent.full) const CustomSemanticsAction(label: 'Expand'): () => _go(up),
        if (at != BBSheetDetent.peek) const CustomSemanticsAction(label: 'Collapse'): () => _go(BBSheetDetent.peek),
        if (widget.dismissible) const CustomSemanticsAction(label: 'Close'): _dismiss,
      },
      child: Center(
        child: Padding(padding: const EdgeInsets.symmetric(vertical: BBSpace.s), child: bar),
      ),
    );
  }

  /// The home sheet's handle (spec 2026-10-14 §3.6): a full-width button, one stop per tap. Expand and Collapse stay
  /// as screen-reader actions, so full height is reachable without a drag.
  Widget _handleButton(BBSheetDetent at, Widget bar) {
    final atPeek = at == BBSheetDetent.peek;
    final target = switch (at) {
      BBSheetDetent.peek => BBSheetDetent.half,
      BBSheetDetent.half => BBSheetDetent.peek,
      BBSheetDetent.full => BBSheetDetent.half,
    };
    void go() => _go(target);
    return Semantics(
      key: BBSheet.handleKey,
      container: true,
      button: true,
      label: atPeek ? 'Show more' : 'Show less',
      onTap: go,
      customSemanticsActions: {
        if (at != BBSheetDetent.full) const CustomSemanticsAction(label: 'Expand'): () => _go(BBSheetDetent.full),
        if (at != BBSheetDetent.peek) const CustomSemanticsAction(label: 'Collapse'): () => _go(BBSheetDetent.peek),
      },
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: go,
        // The bar sits where it always has, centred in the strip above the header.
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(padding: const EdgeInsets.only(top: (BBSheet.handleButtonExtent - 4) / 2), child: bar),
        ),
      ),
    );
  }

  /// The list under the header: scrolled (hairline, shadow, top fade) and more below (bottom fade).
  bool _onList(Notification n) {
    // The rider took hold of the sheet (or its list): what code last asked of it no longer says where it rests.
    if (n is ScrollStartNotification && n.depth == 0 && n.dragDetails != null) {
      _controller._target = null;
      _endQuiet();
    }
    final ScrollMetrics metrics;
    if (n is ScrollNotification && n.depth == 0) {
      metrics = n.metrics;
    } else if (n is ScrollMetricsNotification && n.depth == 0) {
      metrics = n.metrics;
    } else {
      return false;
    }
    final scrolled = metrics.pixels > 0.5;
    final more = metrics.extentAfter > 0.5;
    if (scrolled != _scrolled || more != _moreBelow) {
      // Notifications can arrive mid-layout, where setState is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _scrolled = scrolled;
          _moreBelow = more;
        });
      });
      // A post-frame callback does not schedule a frame: without one, a change that is not a scroll
      // (rows added or removed) would leave the fade stale until something else drew.
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return false;
  }

  Widget _pinnedHeader(BuildContext context) {
    final bb = context.bb;
    // DecoratedBox paints the hairline over the header's own bottom edge: no layout change, so the
    // peek never moves.
    final header = DecoratedBox(
      key: BBSheet.headerKey,
      decoration: BoxDecoration(
        color: bb.colors.surface,
        border: _scrolled ? Border(bottom: BorderSide(color: bb.colors.line)) : null,
        boxShadow: _scrolled
            ? [
                BoxShadow(
                  color: bb.isDark ? const Color(0x59000000) : const Color(0x1A000000),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: widget.handleButton
          // The handle button lies behind the header and reaches 44 pt down over its top: a tap there that no control
          // of the header takes moves the sheet. The strip above the header stays 24 pt, so the bar is no taller.
          ? Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: BBSheet.handleButtonTarget,
                  child: _handle(context),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [const SizedBox(height: BBSheet.handleButtonExtent), ?widget.header],
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_handle(context), ?widget.header],
            ),
    );
    if (!widget.fadeUnderHeader) return header;
    // A strip under the header, surface to clear: the list's top fades under it. The pinned header
    // paints after the list, so the strip lies over it.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        header,
        Positioned(
          key: BBSheet.topFadeKey,
          left: 0,
          right: 0,
          bottom: -BBSheet.topFadeExtent,
          height: BBSheet.topFadeExtent,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _scrolled ? 1 : 0,
              duration: BBMotion.of(context, BBMotion.quick),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bb.colors.surface, bb.colors.surface.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final top = MediaQuery.paddingOf(context).top;
    final peek = widget.peekFraction;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        BBSheet.sideMargin,
        top + BBSpace.s,
        BBSheet.sideMargin,
        widget.bottomInset + BBSpace.s,
      ),
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: _onExtent,
        child: DraggableScrollableSheet(
          controller: _controller,
          initialChildSize: widget.initialFraction ?? peek,
          minChildSize: widget.dismissible ? 0 : peek,
          maxChildSize: widget.fullFraction,
          snap: true,
          snapSizes: _snapSizes,
          snapAnimationDuration: _snapDuration,
          builder: (context, scrollController) {
            final card = bb.floating(radius: BBRadius.sheet);
            // In dark mode the top highlight is the card's edge; paint it in front of the clipped
            // content so the pinned header can't cover it.
            final content = BBSurfaceScope(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BBRadius.sheet),
                child: NotificationListener<Notification>(
                  onNotification: _onList,
                  // The list fades out over its last 24 px while more is below; never at peek, where the
                  // last row showing must stay crisp (spec §5).
                  child: _BottomFade(
                    key: BBSheet.fadeKey,
                    on: _moreBelow && _nearest != BBSheetDetent.peek,
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        PinnedHeaderSliver(child: _pinnedHeader(context)),
                        ...widget.slivers,
                      ],
                    ),
                  ),
                ),
              ),
            );
            return DecoratedBox(
              key: BBSheet.cardKey,
              // Explicit: BoxDecoration.copyWith(border: null) keeps the old border.
              decoration: BoxDecoration(color: card.color, borderRadius: card.borderRadius, boxShadow: card.boxShadow),
              child: card.border == null
                  ? content
                  : DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(border: card.border, borderRadius: card.borderRadius),
                      child: content,
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Fades its child to clear over the last [BBSheet.fadeExtent] when [on]. Off, it paints the child
/// as is, with no offscreen layer. It is one widget either way (swapping a `ShaderMask` in and out
/// would reparent the list and break a drag in flight).
class _BottomFade extends SingleChildRenderObjectWidget {
  const _BottomFade({super.key, required this.on, required super.child});

  final bool on;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBottomFade(on);

  @override
  void updateRenderObject(BuildContext context, _RenderBottomFade renderObject) => renderObject.on = on;
}

class _RenderBottomFade extends RenderProxyBox {
  _RenderBottomFade(this._on);

  bool _on;
  set on(bool value) {
    if (value == _on) return;
    _on = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _on && child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_on || child == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final shaderLayer = layer is ShaderMaskLayer ? layer! as ShaderMaskLayer : ShaderMaskLayer();
    final rect = Offset.zero & size;
    shaderLayer
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: BBSheet.fadeStops(size.height, on: true),
      ).createShader(rect)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    layer = shaderLayer;
    context.pushLayer(shaderLayer, super.paint, offset);
  }
}

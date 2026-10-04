import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum BBSheetDetent { peek, half, full }

/// Drives a [BBSheet]: its size (it is a [DraggableScrollableController]) and
/// detent moves that honour reduce motion.
class BBSheetController extends DraggableScrollableController {
  _BBSheetState? _sheet;

  /// Animates to [detent] (in 1 ms with reduce motion). No-op when detached.
  Future<void> animateToDetent(BBSheetDetent detent) async {
    final sheet = _sheet;
    if (sheet == null || !isAttached) return;
    await animateTo(sheet._fractionOf(detent), duration: sheet._snapDuration, curve: BBMotion.curve);
  }

  /// Back to peek, e.g. when the map behind the sheet is tapped.
  Future<void> collapse() => animateToDetent(BBSheetDetent.peek);
}

/// Floating card sheet with three detents (peek / half / full): inset by
/// [sideMargin], rounded on every corner, lifted above [bottomInset] (the nav
/// bar on the map), with an optional [header] pinned above the scrolling
/// [slivers]. One haptic tick when it settles on a detent. The grab handle is
/// an adjustable control for screen readers (Expand / Collapse / Close).
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
  final bool dismissible;
  final VoidCallback? onDismiss;
  final String semanticLabel;

  static const double sideMargin = 8;
  static const cardKey = ValueKey('bb-sheet-card');
  static const handleKey = ValueKey('bb-sheet-handle');

  @override
  State<BBSheet> createState() => _BBSheetState();
}

class _BBSheetState extends State<BBSheet> {
  static const _tolerance = 0.004;
  static const _settleDelay = Duration(milliseconds: 80);

  late final BBSheetController _controller = widget.controller ?? BBSheetController();
  late double? _lastDetent = widget.initialFraction ?? widget.peekFraction;
  late double _extent = widget.initialFraction ?? widget.peekFraction;
  Timer? _settleTimer;
  bool _dismissed = false;
  Duration _snapDuration = BBMotion.sheet;

  @override
  void initState() {
    super.initState();
    _controller._sheet = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The sheet API rejects Duration.zero, so "reduce motion" uses 1 ms.
    final d = BBMotion.of(context, BBMotion.sheet);
    _snapDuration = d == Duration.zero ? const Duration(milliseconds: 1) : d;
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
    if (widget.dismissible && n.extent < _tolerance) {
      _settleTimer = Timer(_settleDelay, _dismiss);
      return false;
    }
    final detent = _detentNear(n.extent);
    if (detent == null) {
      _lastDetent = null;
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
      increasedValue: _valueOf(up),
      decreasedValue: _valueOf(down),
      onIncrease: at == BBSheetDetent.full ? null : () => _go(up),
      onDecrease: at == BBSheetDetent.peek ? (widget.dismissible ? _dismiss : null) : () => _go(down),
      customSemanticsActions: {
        if (at != BBSheetDetent.full) const CustomSemanticsAction(label: 'Expand'): () => _go(up),
        if (at != BBSheetDetent.peek) const CustomSemanticsAction(label: 'Collapse'): () => _go(BBSheetDetent.peek),
        if (widget.dismissible) const CustomSemanticsAction(label: 'Close'): _dismiss,
      },
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: BBSpace.s, bottom: BBSpace.s),
          width: 34,
          height: 4,
          decoration: BoxDecoration(color: bb.colors.line, borderRadius: BorderRadius.circular(2)),
        ),
      ),
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
          snapSizes: widget.dismissible ? [peek, widget.halfFraction] : [widget.halfFraction],
          snapAnimationDuration: _snapDuration,
          builder: (context, scrollController) => DecoratedBox(
            key: BBSheet.cardKey,
            decoration: bb.floating(radius: BBRadius.sheet),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BBRadius.sheet),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  PinnedHeaderSliver(
                    child: ColoredBox(
                      color: bb.colors.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_handle(context), ?widget.header],
                      ),
                    ),
                  ),
                  ...widget.slivers,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

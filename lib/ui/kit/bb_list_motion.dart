import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// List motion (spec §3.2). Wrap a list's Column in [BBListMotion] and each item in a keyed
/// [BBListItem]:
/// - the first time the list shows items, they enter one after another ([BBMotion.stagger]
///   apart, at most [BBMotion.staggerMax] steps, each a [BBMotion.standard] fade and rise);
/// - items that appear later (a live refresh) show at once;
/// - with [slide], an item whose place changes (the list reorders, a row above it goes) slides
///   from its old place to its new one.
/// Reduce Motion turns all of it off.
class BBListMotion extends StatefulWidget {
  const BBListMotion({super.key, required this.child, this.slide = true});

  final Widget child;

  /// Slide moved items. Off for lazily built scrolling lists, where scrolling itself moves items.
  final bool slide;

  @override
  State<BBListMotion> createState() => _BBListMotionState();
}

class _EntranceGate {
  bool open = true;
  bool closing = false;
}

class _BBListMotionState extends State<BBListMotion> {
  final _gate = _EntranceGate();

  @override
  Widget build(BuildContext context) => _ListMotionScope(
        gate: _gate,
        child: widget.slide ? _MoveAnchor(child: widget.child) : widget.child,
      );
}

class _ListMotionScope extends InheritedWidget {
  const _ListMotionScope({required this.gate, required super.child});

  final _EntranceGate gate;

  @override
  bool updateShouldNotify(_ListMotionScope oldWidget) => false;
}

/// The frame of reference for [RenderBBSlideOnMove]: places are measured from here, so
/// scrolling the whole list never counts as a move.
class _MoveAnchor extends SingleChildRenderObjectWidget {
  const _MoveAnchor({super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) => _RenderMoveAnchor();
}

class _RenderMoveAnchor extends RenderProxyBox {}

/// One item of a [BBListMotion] list. [index] is its place, for the entrance stagger.
class BBListItem extends StatefulWidget {
  const BBListItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<BBListItem> createState() => _BBListItemState();
}

class _BBListItemState extends State<BBListItem> with SingleTickerProviderStateMixin {
  AnimationController? _entrance;
  CurvedAnimation? _shown;
  bool _decided = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = BBMotion.reduced(context);
    if (_decided) return;
    _decided = true;
    final gate = context.getInheritedWidgetOfExactType<_ListMotionScope>()?.gate;
    if (gate == null || !gate.open || _reduced) return;
    if (!gate.closing) {
      gate.closing = true;
      // Everything that mounts in this first frame enters; anything later shows at once.
      WidgetsBinding.instance.addPostFrameCallback((_) => gate.open = false);
    }
    final delay = BBMotion.stagger * math.min(widget.index, BBMotion.staggerMax);
    final total = delay + BBMotion.standard;
    final controller = AnimationController(vsync: this, duration: total)..forward();
    _entrance = controller;
    _shown = CurvedAnimation(
      parent: controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: BBMotion.curve),
    );
  }

  @override
  void dispose() {
    _shown?.dispose();
    _entrance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var child = widget.child;
    final shown = _shown;
    if (shown != null) {
      child = FadeTransition(
        opacity: shown,
        child: SlideTransition(
          position: shown.drive(Tween(begin: const Offset(0, 0.15), end: Offset.zero)),
          child: child,
        ),
      );
    }
    // Outermost, so the slide tracks the laid-out place, not the entrance's own rise.
    return BBSlideOnMove(enabled: !_reduced, child: child);
  }
}

/// Paints its child sliding from where it was last painted to where it is now, measured from
/// the nearest [BBListMotion], over [BBMotion.standard]. Used by [BBListItem].
class BBSlideOnMove extends SingleChildRenderObjectWidget {
  const BBSlideOnMove({super.key, required this.enabled, super.child});

  final bool enabled;

  @override
  RenderBBSlideOnMove createRenderObject(BuildContext context) => RenderBBSlideOnMove(enabled);

  @override
  void updateRenderObject(BuildContext context, RenderBBSlideOnMove renderObject) =>
      renderObject.enabled = enabled;
}

/// See [BBSlideOnMove]. The slide is paint-only: layout and hit testing use the new place at
/// once, so a tap mid-slide reaches the row that is really there.
class RenderBBSlideOnMove extends RenderProxyBox {
  RenderBBSlideOnMove(this._enabled);

  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _from = Offset.zero;
    _start = null;
    markNeedsPaint();
  }

  Offset? _lastPlace;
  Offset _from = Offset.zero;
  Duration? _start;

  /// How far from its laid-out place the child was last painted (zero when still).
  @visibleForTesting
  Offset lastShift = Offset.zero;

  Offset _shiftAt(Duration now) {
    final start = _start;
    if (start == null) return Offset.zero;
    final t = ((now - start).inMicroseconds / BBMotion.standard.inMicroseconds).clamp(0.0, 1.0);
    return t >= 1 ? Offset.zero : _from * (1 - BBMotion.curve.transform(t));
  }

  RenderObject? get _anchor {
    var node = parent;
    while (node != null && node is! _RenderMoveAnchor) {
      node = node.parent;
    }
    return node;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final anchor = _anchor;
    if (_enabled && anchor != null) {
      final t = getTransformTo(anchor).getTranslation();
      final place = Offset(t.x, t.y);
      final last = _lastPlace;
      _lastPlace = place;
      if (last != null && (last - place).distance > 0.5) {
        // Start from wherever the child shows now, mid-slide included.
        _from = last - place + _shiftAt(now);
        _start = now;
      }
    }
    final shift = _enabled ? _shiftAt(now) : Offset.zero;
    if (shift == Offset.zero) {
      _start = null;
    } else {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (attached) markNeedsPaint();
      });
    }
    lastShift = shift;
    super.paint(context, offset + shift);
  }
}

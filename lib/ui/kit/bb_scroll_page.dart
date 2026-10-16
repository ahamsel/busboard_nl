import 'dart:ui' show ImageFilter;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'bb_top_bar.dart';
import 'tokens.dart';

/// A pushed page (Alerts, Settings, Search) whose content scrolls under its top bar (spec §5).
/// At rest the bar is clear over `bg`, with the large title. Once content scrolls under it, the
/// title condenses (at once under Reduce Motion), and the bar frosts (blur 16, `bg` at 80%) and
/// gets a `line` hairline. [below] (Search's field) sits in the bar, under the title.
///
/// [body] builds the scrolling content. Pad its top by `topInset` (the bar's height), so its first
/// item starts below the bar and scrolls up under it.
class BBScrollPage extends StatefulWidget {
  const BBScrollPage({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.large = false,
    this.below,
    required this.body,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool large;
  final Widget? below;
  final Widget Function(BuildContext context, double topInset) body;

  static const barKey = ValueKey('bb-scroll-page-bar');

  @override
  State<BBScrollPage> createState() => _BBScrollPageState();
}

class _BBScrollPageState extends State<BBScrollPage> {
  bool _under = false;
  double _inset = 0;

  /// The list is back at the top and the title is growing back to large: the bar passes through
  /// every height on the way, and the inset must not follow it down (the content would dip).
  bool _returning = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final under = n.metrics.pixels > 0.5;
    if (under != _under) {
      setState(() {
        _under = under;
        _returning = !under;
      });
    }
    return false;
  }

  /// The inset for a bar [height], called as the page lays out, right after the bar and before the body is built:
  /// the first row is placed under the bar in the same frame the bar first appears.
  ///
  /// It follows the bar at rest only: while condensed the bar is shorter, and moving the list's padding then would
  /// make the content jump. On the way back to large it may only grow, and the first height that reaches the
  /// resting inset ends the return.
  double _insetFor(double height) {
    if (_under) return _inset;
    if (_returning) {
      if (height < _inset - 0.5) return _inset;
      _returning = false;
    }
    if ((height - _inset).abs() > 0.5) _inset = height;
    return _inset;
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final under = _under;
    return _BarThenBody(
      insetFor: _insetFor,
      // The bar paints over the body, and is the part that the body's top inset makes room for.
      bar: ClipRect(
        child: BackdropFilter(
          enabled: under,
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            key: BBScrollPage.barKey,
            decoration: BoxDecoration(
              color: under ? bb.colors.bg.withValues(alpha: 0.8) : const Color(0x00000000),
              border: under ? Border(bottom: BorderSide(color: bb.colors.line)) : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BBTopBar(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  onBack: widget.onBack,
                  actions: widget.actions,
                  large: widget.large,
                  condensed: under,
                ),
                ?widget.below,
              ],
            ),
          ),
        ),
      ),
      body: (context, inset) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.body(context, inset),
      ),
    );
  }
}

enum _Slot { bar, body }

/// The page's two layers: the [bar], laid out first, and the [body], which is built during layout, once the bar's
/// height is known, and given it (through [insetFor]) as its top inset. So the body's first frame is already right:
/// no estimate of the bar's height, which wrapped titles and a `below` widget would make wrong, and no frame spent
/// waiting for a measurement. The bar paints over the body.
class _BarThenBody extends RenderObjectWidget {
  const _BarThenBody({required this.bar, required this.body, required this.insetFor});

  final Widget bar;
  final Widget Function(BuildContext context, double inset) body;
  final double Function(double barHeight) insetFor;

  @override
  RenderObjectElement createElement() => _BarThenBodyElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBarThenBody();
}

class _BarThenBodyElement extends RenderObjectElement {
  _BarThenBodyElement(_BarThenBody super.widget);

  @override
  _BarThenBody get widget => super.widget as _BarThenBody;

  @override
  _RenderBarThenBody get renderObject => super.renderObject as _RenderBarThenBody;

  Element? _bar;
  Element? _body;
  double? _builtInset;
  bool _needsBody = true;

  // The body is built inside layout, like a LayoutBuilder's child, so it has a build scope of its own: anything
  // below it that marks itself dirty is rebuilt in the next layout, not in the ordinary build phase.
  @override
  BuildScope get buildScope => _buildScope;
  late final BuildScope _buildScope = BuildScope(scheduleRebuild: _scheduleRebuild);

  bool _deferred = false;

  void _scheduleRebuild() {
    if (_deferred) return;
    final defer = switch (SchedulerBinding.instance.schedulerPhase) {
      SchedulerPhase.idle || SchedulerPhase.postFrameCallbacks => true,
      SchedulerPhase.transientCallbacks ||
      SchedulerPhase.midFrameMicrotasks ||
      SchedulerPhase.persistentCallbacks => false,
    };
    if (!defer) {
      renderObject.markNeedsLayout();
      return;
    }
    // The render tree stays clean outside a frame; mark it at the start of the next one.
    _deferred = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _deferred = false;
      if (mounted) renderObject.markNeedsLayout();
    });
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_bar != null) visitor(_bar!);
    if (_body != null) visitor(_body!);
  }

  @override
  void forgetChild(Element child) {
    if (child == _bar) _bar = null;
    if (child == _body) _body = null;
    super.forgetChild(child);
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot); // creates the render object
    _bar = updateChild(_bar, widget.bar, _Slot.bar);
    renderObject._flush = _flush;
    renderObject._callback = _layoutCallback;
  }

  @override
  void update(_BarThenBody newWidget) {
    super.update(newWidget);
    _bar = updateChild(_bar, widget.bar, _Slot.bar);
    renderObject._flush = _flush;
    renderObject._callback = _layoutCallback;
    _needsBody = true;
    renderObject.markNeedsLayout();
  }

  // Not a rebuild of this element: the body is rebuilt in layout. This is called when something the body builder
  // depends on (an inherited widget) changes.
  @override
  void markNeedsBuild() {
    _needsBody = true;
    renderObject.markNeedsLayout();
  }

  @override
  void performRebuild() {
    _needsBody = true;
    renderObject.markNeedsLayout();
    super.performRebuild();
  }

  @override
  void unmount() {
    renderObject._flush = null;
    renderObject._callback = null;
    super.unmount();
  }

  /// Rebuilds what below the bar or the body marked dirty (they share this element's build scope), before the bar is
  /// laid out: otherwise the bar would be laid out and then rebuilt, and left needing layout.
  void _flush() => owner!.buildScope(this);

  /// Called from the render object's layout with the bar's height: builds the body if it, or its inset, changed.
  void _layoutCallback(double barHeight) {
    final inset = widget.insetFor(barHeight);
    final build = _needsBody || inset != _builtInset;
    owner!.buildScope(this, build ? () => _buildBody(inset) : null);
  }

  void _buildBody(double inset) {
    Widget built;
    try {
      built = widget.body(this, inset);
    } catch (e, stack) {
      built = _error(e, stack);
    }
    try {
      _body = updateChild(_body, built, _Slot.body);
    } catch (e, stack) {
      _body = updateChild(null, _error(e, stack), _Slot.body);
    } finally {
      _needsBody = false;
      _builtInset = inset;
    }
  }

  Widget _error(Object e, StackTrace stack) => ErrorWidget.builder(
        FlutterErrorDetails(
          exception: e,
          stack: stack,
          library: 'BusBoard kit',
          context: ErrorDescription('building the body of $widget'),
        ),
      );

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    final box = child as RenderBox;
    switch (slot! as _Slot) {
      case _Slot.bar:
        renderObject.bar = box;
      case _Slot.body:
        renderObject.body = box;
    }
  }

  @override
  void moveRenderObjectChild(RenderObject child, Object? oldSlot, Object? newSlot) {
    assert(false, 'the bar and the body never swap places');
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    switch (slot! as _Slot) {
      case _Slot.bar:
        renderObject.bar = null;
      case _Slot.body:
        renderObject.body = null;
    }
  }
}

class _RenderBarThenBody extends RenderBox {
  RenderBox? _bar;
  RenderBox? _body;
  void Function()? _flush;
  void Function(double barHeight)? _callback;

  set bar(RenderBox? value) {
    if (_bar != null) dropChild(_bar!);
    _bar = value;
    if (value != null) adoptChild(value);
  }

  set body(RenderBox? value) {
    if (_body != null) dropChild(_body!);
    _body = value;
    if (value != null) adoptChild(value);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _bar?.attach(owner);
    _body?.attach(owner);
  }

  @override
  void detach() {
    super.detach();
    _bar?.detach();
    _body?.detach();
  }

  @override
  void redepthChildren() {
    if (_bar != null) redepthChild(_bar!);
    if (_body != null) redepthChild(_body!);
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    if (_body != null) visitor(_body!);
    if (_bar != null) visitor(_bar!);
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    final bar = _bar;
    if (bar == null) return;
    // Anything dirty below is rebuilt first, so what is laid out next is what stays.
    final flush = _flush;
    if (flush != null) invokeLayoutCallback<BoxConstraints>((_) => flush());
    // The bar, at the page's width and as tall as it needs.
    bar.layout(BoxConstraints(minWidth: size.width, maxWidth: size.width, maxHeight: size.height), parentUsesSize: true);
    // Then the body, built now that the bar's height is known.
    final callback = _callback;
    if (callback != null) invokeLayoutCallback<BoxConstraints>((_) => callback(bar.size.height));
    _body?.layout(BoxConstraints.tight(size));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_body != null) context.paintChild(_body!, offset);
    if (_bar != null) context.paintChild(_bar!, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // The bar is on top: it gets the first chance.
    for (final child in [_bar, _body]) {
      if (child != null && child.hitTest(result, position: position)) return true;
    }
    return false;
  }
}

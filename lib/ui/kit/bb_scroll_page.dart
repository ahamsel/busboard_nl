import 'dart:ui' show ImageFilter;

import 'package:flutter/rendering.dart';
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

  /// The inset follows the bar at rest only: while condensed the bar is shorter, and moving the
  /// list's padding then would make the content jump. On the way back to large it may only grow,
  /// and the first height that reaches the resting inset ends the return.
  void _onBarHeight(double height) {
    if (!mounted || _under) return;
    if (_returning) {
      if (height < _inset - 0.5) return;
      _returning = false;
    }
    if ((height - _inset).abs() <= 0.5) return;
    setState(() => _inset = height);
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final under = _under;
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.body(context, _inset),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              enabled: under,
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: DecoratedBox(
                key: BBScrollPage.barKey,
                decoration: BoxDecoration(
                  color: under ? bb.colors.bg.withValues(alpha: 0.8) : const Color(0x00000000),
                  border: under ? Border(bottom: BorderSide(color: bb.colors.line)) : null,
                ),
                child: _MeasureHeight(
                  onHeight: _onBarHeight,
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
          ),
        ),
      ],
    );
  }
}

/// Reports its child's height after each layout that changes it.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureHeight renderObject) => renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    // Not during layout: the page rebuilds with the new inset after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

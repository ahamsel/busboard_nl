import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Tap target with a press-scale + dim instead of a ripple (spec §5.1).
class BBPressable extends StatefulWidget {
  const BBPressable({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.haptic = false,
    this.exposeSemantics = true,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// When set, replaces the child's own semantics.
  final String? semanticLabel;
  final bool haptic;

  /// False leaves the tap to a descendant's own semantics (a row that restates its
  /// tap on its content), so no unlabeled duplicate "button" node is added.
  final bool exposeSemantics;

  @override
  State<BBPressable> createState() => _BBPressableState();
}

class _BBPressableState extends State<BBPressable> {
  bool _down = false;

  @override
  void didUpdateWidget(BBPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Disabled mid-press: the gesture callbacks are gone, so nothing would
    // ever clear the pressed look.
    if (widget.onTap == null) _down = false;
  }

  void _setDown(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  void _handleTap() {
    if (widget.haptic) HapticFeedback.selectionClick();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final duration = BBMotion.of(context, BBMotion.quick);
    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // The tap reaches screen readers through the Semantics below (or a descendant's own): a second tap action
      // here would split the button into a bare "button" node around a separate labelled one.
      excludeFromSemantics: true,
      onTapDown: enabled ? (_) => _setDown(true) : null,
      onTapUp: enabled ? (_) => _setDown(false) : null,
      onTapCancel: enabled ? () => _setDown(false) : null,
      onTap: enabled ? _handleTap : null,
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: duration,
        curve: BBMotion.curve,
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1,
          duration: duration,
          child: widget.child,
        ),
      ),
    );
    if (!widget.exposeSemantics) return gesture;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: enabled ? _handleTap : null,
      excludeSemantics: widget.semanticLabel != null,
      child: gesture,
    );
  }
}

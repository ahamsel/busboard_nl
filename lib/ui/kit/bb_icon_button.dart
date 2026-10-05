import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

/// Icon-only button with a 44pt target and a required screen-reader label.
class BBIconButton extends StatelessWidget {
  const BBIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
    this.size = 22,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    // Opacity sits inside BBPressable so the labelled Semantics node stays the
    // outermost one (the same dimming BBButton applies when disabled).
    return BBPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Icon(icon, size: size, color: color ?? c.ink),
          ),
        ),
      ),
    );
  }
}

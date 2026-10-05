import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

enum BBButtonKind { primary, quiet }

class BBButton extends StatelessWidget {
  const BBButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = BBButtonKind.primary,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BBButtonKind kind;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final primary = kind == BBButtonKind.primary;
    final fg = primary ? bb.colors.onBrand : bb.colors.brandInk;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: BBSpace.s),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: bb.text.label.copyWith(color: fg, fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: BBPressable(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          alignment: expand ? Alignment.center : null,
          decoration: primary
              ? BoxDecoration(color: bb.colors.brand, borderRadius: BorderRadius.circular(BBRadius.button))
              : null,
          child: content,
        ),
      ),
    );
  }
}

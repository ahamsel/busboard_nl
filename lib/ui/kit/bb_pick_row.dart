import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

/// One tappable row of a place list: an icon and a label. A null [onTap] dims it.
class BBPickRow extends StatelessWidget {
  const BBPickRow({super.key, required this.icon, required this.label, required this.onTap, this.semanticLabel});

  final IconData icon;
  final String label;
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return BBPressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: BBSpace.s),
            child: Row(
              children: [
                Icon(icon, size: 20, color: bb.colors.muted),
                const SizedBox(width: BBSpace.m),
                Expanded(child: Text(label, style: bb.text.body)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

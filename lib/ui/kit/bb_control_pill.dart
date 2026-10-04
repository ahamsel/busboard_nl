import 'package:flutter/widgets.dart';

import 'bb_icon_button.dart';
import 'tokens.dart';

class BBControlPillItem {
  const BBControlPillItem({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool selected;
}

/// Vertical stack of 44 pt map controls on one floating pill (e.g. "my
/// location"), separated by hairlines. A selected item uses the brand colour.
class BBControlPill extends StatelessWidget {
  const BBControlPill({super.key, required this.items});

  final List<BBControlPillItem> items;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return DecoratedBox(
      decoration: bb.floating(radius: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 28, height: 1, color: bb.colors.line),
            Semantics(
              selected: items[i].selected,
              child: BBIconButton(
                icon: items[i].icon,
                semanticLabel: items[i].semanticLabel,
                onPressed: items[i].onPressed,
                color: items[i].selected ? bb.colors.brand : bb.colors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

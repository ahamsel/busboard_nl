import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

class BBNavItem {
  const BBNavItem({required this.label, required this.icon, this.badgeCount = 0});
  final String label;
  final IconData icon;
  final int badgeCount;
}

/// White floating pill bar; the active tab is a full Harbour Blue pill.
class BBNavBar extends StatelessWidget {
  const BBNavBar({super.key, required this.items, required this.currentIndex, required this.onSelect});

  final List<BBNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const double height = 56;

  /// Gap between the bar and the bottom safe area.
  static const double gap = 16;

  /// Bottom space a screen must leave free so content isn't hidden by the bar.
  static double reservedHeight(BuildContext context) =>
      height + gap + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, gap + MediaQuery.paddingOf(context).bottom),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(5),
        decoration: bb.floating(radius: BBRadius.sheet),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _Tab(item: items[i], selected: i == currentIndex, onTap: () => onSelect(i)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.onTap});

  final BBNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fg = selected ? bb.colors.onBrand : bb.colors.muted;
    final label = item.badgeCount > 0 ? '${item.label}, ${item.badgeCount} active' : item.label;
    return Semantics(
      selected: selected,
      child: BBPressable(
        onTap: onTap,
        haptic: true,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: BBMotion.of(context, BBMotion.standard),
          curve: BBMotion.curve,
          decoration: BoxDecoration(
            color: selected ? bb.colors.brand : null,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(item.label, maxLines: 1, style: bb.text.label.copyWith(color: fg)),
                if (item.badgeCount > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: bb.colors.dangerInk, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '${item.badgeCount}',
                      textAlign: TextAlign.center,
                      style: bb.text.caption.copyWith(
                        color: bb.colors.surface,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

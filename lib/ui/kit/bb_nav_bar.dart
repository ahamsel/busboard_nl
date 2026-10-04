import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

class BBNavItem {
  const BBNavItem({required this.label, required this.icon, this.activeIcon, this.badgeCount = 0});
  final String label;
  final IconData icon;

  /// Shown while the tab is selected (the fill weight); defaults to [icon].
  final IconData? activeIcon;
  final int badgeCount;
}

/// White floating pill bar; the active tab is a full Harbour Blue pill.
class BBNavBar extends StatelessWidget {
  const BBNavBar({super.key, required this.items, required this.currentIndex, required this.onSelect});

  final List<BBNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// Bar height at text scale 1.0.
  static const double height = 56;

  /// Largest text scale the bar follows; beyond it the labels stop growing so
  /// all three tabs stay the same size and the bar stays compact.
  static const double maxTextScale = 1.3;

  /// Gap between the bar and the bottom safe area.
  static const double gap = 16;

  /// Bar height for the current text scale: 56 at 1.0, growing with the
  /// (clamped) text so the labels keep their padding and a 44pt target.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, maxTextScale);
    return height * scale;
  }

  /// Bottom space a screen must leave free so content isn't hidden by the bar.
  static double reservedHeight(BuildContext context) =>
      heightFor(context) + gap + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, gap + MediaQuery.paddingOf(context).bottom),
          child: Container(
            height: heightFor(context),
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
                Icon(selected ? (item.activeIcon ?? item.icon) : item.icon, size: 18, color: fg),
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

/// Marks the subtree where the floating nav bar is on screen (the tab shell).
/// Overlays such as [BBToast] reserve the bar's height only inside it, so a
/// pushed screen without the bar (Settings) doesn't float its toasts high.
class BBNavBarScope extends InheritedWidget {
  const BBNavBarScope({super.key, required super.child});

  static bool isPresent(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BBNavBarScope>() != null;

  @override
  bool updateShouldNotify(BBNavBarScope oldWidget) => false;
}

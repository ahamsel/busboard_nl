import 'dart:ui' show SemanticsRole;

import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

/// One tab of a [BBTabBar]: its [label], its [icon], and the [activeIcon] it shows while selected.
@immutable
class BBTab {
  const BBTab({required this.label, required this.icon, required this.activeIcon, this.key});

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// The tab's own key, for tests.
  final Key? key;
}

/// The bottom tab bar (spec 2026-10-15 §2.1): at least [height] pt tall plus the bottom safe area, on `surface` with a
/// `line` hairline on top. Inactive tabs are `muted`; the active one is `brandInk`, its filled icon on a `brandSoft`
/// pill, so the selection never rests on colour alone. Each tab is a button with a selected state that screen readers
/// read as "Board, tab 1 of 2, selected". The pill cross-fades over [BBMotion.standard], at once under Reduce Motion.
/// Labels grow with the text size, and the bar grows with them. On a wide screen the bar still spans it, but its tabs
/// keep to a centred row [maxRowWidth] wide, so the two never sit half a tablet apart.
class BBTabBar extends StatelessWidget {
  const BBTabBar({super.key, required this.tabs, required this.index, required this.onSelect});

  final List<BBTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// The bar's height above the bottom safe area, at 1x text.
  static const double height = 56;

  /// The widest the row of tabs gets (a tablet, a phone on its side).
  static const double maxRowWidth = 480;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bb.colors.surface,
        border: Border(top: BorderSide(color: bb.colors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Semantics(
          role: SemanticsRole.tabBar,
          container: true,
          explicitChildNodes: true,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height, maxWidth: maxRowWidth),
              // Both tabs as tall as the taller one, and the whole height theirs to tap.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, tab) in tabs.indexed)
                      Expanded(
                        child: _TabButton(
                          key: tab.key,
                          tab: tab,
                          active: i == index,
                          semanticLabel: '${tab.label}, tab ${i + 1} of ${tabs.length}',
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.active,
    required this.semanticLabel,
    required this.onTap,
  });

  final BBTab tab;
  final bool active;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fg = active ? bb.colors.brandInk : bb.colors.muted;
    return Semantics(
      role: SemanticsRole.tab,
      button: true,
      selected: active,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: BBPressable(
        exposeSemantics: false,
        haptic: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BBSpace.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: BBMotion.of(context, BBMotion.standard),
                curve: BBMotion.curve,
                width: 56,
                height: 28,
                decoration: BoxDecoration(
                  color: active ? bb.colors.brandSoft : bb.colors.brandSoft.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(active ? tab.activeIcon : tab.icon, size: 22, color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bb.text.label.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

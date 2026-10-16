import 'dart:math' as math;
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

/// The bottom tab bar as a floating capsule switch (tab bar option B, 2026-10-16): a fully rounded capsule
/// [sideInset] pt in from each side and [gap] pt above the bottom safe area, at most [maxWidth] wide and centred,
/// with no full-width band or hairline. Light: `surfaceFloat` with a 1 px `line` outline and the soft float shadow;
/// dark: the map controls' float (deep shadow, top-edge highlight). Inside, [padding] pt in, a `brand` thumb sits
/// behind the selected half, whose filled icon and label are `onBrand`; the other half is `muted` on the capsule. The
/// thumb slides between halves over [BBMotion.standard], as [BBSegmented]'s pill does, and at once under Reduce
/// Motion. Each half is a button with a selected state that screen readers read as "Board, tab 1 of 2, selected".
///
/// The capsule is [height] pt tall at 1x text and grows with the labels: side by side with the icon while they fit,
/// the label under the icon (and then wrapped) when they don't, never clipped.
///
/// The widget itself spans the width and runs from the capsule's top edge to the bottom of the screen (margins and
/// safe area included), so its top is the capsule's top. Its margins take no taps. Lay it out over the content with
/// [BBTabBarLayout], which tells the content how much of the bottom the capsule needs.
class BBTabBar extends StatelessWidget {
  const BBTabBar({super.key, required this.tabs, required this.index, required this.onSelect});

  final List<BBTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// The capsule's height at 1x text.
  static const double height = 52;

  /// Between the capsule's edge and the thumb: each half is [height] - 2 × [padding] = 44 pt tall at least.
  static const double padding = 4;

  /// From the screen's sides to the capsule.
  static const double sideInset = 16;

  /// From the bottom safe area to the capsule.
  static const double gap = 8;

  /// The widest the capsule gets (a tablet, a phone on its side).
  static const double maxWidth = 360;

  static const capsuleKey = ValueKey('bb-tab-bar-capsule');
  static const thumbKey = ValueKey('bb-tab-bar-thumb');

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final safe = MediaQuery.paddingOf(context);
    final n = tabs.length;
    // The map controls' float. In light the capsule is white on a near-white page, so it also takes a `line` outline.
    final float = bb.mapControl(radius: 999);
    final decoration = bb.isDark ? float : float.copyWith(border: Border.all(color: bb.colors.line));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        math.max(sideInset, safe.left),
        0,
        math.max(sideInset, safe.right),
        safe.bottom + gap,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Semantics(
            role: SemanticsRole.tabBar,
            container: true,
            explicitChildNodes: true,
            child: DecoratedBox(
              key: capsuleKey,
              decoration: decoration,
              child: Padding(
                padding: const EdgeInsets.all(padding),
                // Both halves as tall as the taller one, and so is the thumb.
                child: IntrinsicHeight(
                  child: Stack(
                    children: [
                      if (n > 0 && index >= 0 && index < n)
                        Positioned.fill(
                          child: AnimatedAlign(
                            key: thumbKey,
                            duration: BBMotion.of(context, BBMotion.standard),
                            curve: BBMotion.curve,
                            // Directional, so in a right-to-left layout the thumb follows the mirrored Row.
                            alignment: AlignmentDirectional(n <= 1 ? 0 : -1 + 2 * index / (n - 1), 0),
                            child: FractionallySizedBox(
                              widthFactor: 1 / n,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: bb.colors.brand,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, tab) in tabs.indexed)
                            Expanded(
                              child: _TabButton(
                                key: tab.key,
                                tab: tab,
                                active: i == index,
                                semanticLabel: '${tab.label}, tab ${i + 1} of $n',
                                onTap: () => onSelect(i),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: BBTabBar.height - 2 * BBTabBar.padding),
          // The ink turns as the thumb slides under it (at once under Reduce Motion).
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: active ? bb.colors.onBrand : bb.colors.muted),
            duration: BBMotion.of(context, BBMotion.standard),
            curve: BBMotion.curve,
            builder: (context, fg, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.xs),
              child: Center(
                // Icon and label side by side; when the half is too narrow for both (large text), the label goes
                // under the icon, and wraps if it must.
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Icon(active ? tab.activeIcon : tab.icon, size: 22, color: fg),
                    Text(
                      tab.label,
                      textAlign: TextAlign.center,
                      style: bb.text.label.copyWith(color: fg),
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

enum _Slot { body, bar }

/// A [BBTabBar] floating over the [body]: the bar is laid out first, at the bottom, and the body is then built at the
/// full size behind it with `inset`, the bar's height (from the capsule's top edge to the bottom of the screen, safe
/// area included). The body reserves that much at its bottom (as its bottom padding), so what sits on it clears the
/// capsule, and what scrolls can scroll out from behind it. The bar paints over the body and gets touches first; its
/// margins pass them through to the body.
class BBTabBarLayout extends StatelessWidget {
  const BBTabBarLayout({super.key, required this.bar, required this.body});

  final Widget bar;
  final Widget Function(BuildContext context, double inset) body;

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _BarOverBody(),
      children: [
        LayoutId(
          id: _Slot.body,
          // Built during layout, once the bar is measured: the bar's height reaches it as the gap between its
          // constraints' least and greatest heights (see _BarOverBody), so a change rebuilds it in the same frame.
          child: LayoutBuilder(
            builder: (context, c) => SizedBox(
              width: c.maxWidth,
              height: c.maxHeight,
              child: body(context, c.maxHeight - c.minHeight),
            ),
          ),
        ),
        LayoutId(id: _Slot.bar, child: bar),
      ],
    );
  }
}

class _BarOverBody extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final bar = layoutChild(
      _Slot.bar,
      BoxConstraints(minWidth: size.width, maxWidth: size.width, maxHeight: size.height),
    );
    positionChild(_Slot.bar, Offset(0, size.height - bar.height));
    // Full size (it fills the box), with the bar's height carried in the slack between minHeight and maxHeight.
    layoutChild(
      _Slot.body,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: math.max(0, size.height - bar.height),
        maxHeight: size.height,
      ),
    );
    positionChild(_Slot.body, Offset.zero);
  }

  @override
  bool shouldRelayout(_BarOverBody oldDelegate) => false;
}

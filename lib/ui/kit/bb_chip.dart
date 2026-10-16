import 'package:flutter/widgets.dart';

import 'bb_card.dart';
import 'bb_icons.dart';
import 'bb_pressable.dart';
import 'tokens.dart';

/// Floating map chip (your stop, route filter, "Back to bus"): a 44 pt pill on
/// the floating surface. [selected] uses the brand fill, cross-fading over BBMotion.standard. [leading] (e.g. a
/// [BBGlyph]) replaces [icon].
///
/// The parent must bound the chip's width (e.g. Positioned with both left and
/// right, or a ConstrainedBox); the label ellipsizes within it.
class BBChip extends StatelessWidget {
  const BBChip({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.chevron = false,
    this.selected = false,
    this.onTap,
    this.semanticLabel,
    this.toggle = false,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool chevron;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// One of a set the rider picks from (the Board's stop chips): screen readers hear "selected" or "not selected".
  /// An ordinary chip is a plain button, with no selected state until it is selected.
  final bool toggle;

  static const surfaceKey = ValueKey('bb-chip-surface');

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fg = selected ? bb.colors.onBrand : bb.colors.ink;
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 18, color: selected ? fg : bb.colors.brandInk));
    // Null (not false) when unselected: an ordinary button is not a toggle.
    return Semantics(
      selected: toggle ? selected : (selected ? true : null),
      child: BBPressable(
        onTap: onTap,
        semanticLabel: semanticLabel ?? label,
        child: AnimatedContainer(
          key: surfaceKey,
          duration: BBMotion.of(context, BBMotion.standard),
          curve: BBMotion.curve,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: BBSpace.l, vertical: BBSpace.s),
          // On the map a chip floats; on a sheet it is a field-surface pill (spec §2.1).
          decoration: BBSurfaceScope.isRaised(context)
              ? (selected
                  ? BoxDecoration(color: bb.colors.brand, borderRadius: BorderRadius.circular(22))
                  : bb.field(radius: 22))
              : bb.mapControl(selected: selected),
          // Selected: a 1.5 px brandEdge border too, since the bright fill alone is ~2.85:1 on white (WCAG 1.4.11).
          // Drawn over the chip, so it never changes the chip's size.
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: bb.brandEdge, width: 1.5),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lead != null) ...[lead, const SizedBox(width: BBSpace.s)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bb.text.label.copyWith(color: fg),
                ),
              ),
              if (chevron) ...[
                const SizedBox(width: BBSpace.xs),
                Icon(BBIcons.chevronDown, size: 16, color: selected ? fg : bb.colors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

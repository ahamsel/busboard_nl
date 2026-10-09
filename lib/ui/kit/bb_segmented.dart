import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

class BBSegment<T> {
  const BBSegment({required this.value, required this.label});
  final T value;
  final String label;
}

class BBSegmented<T> extends StatelessWidget {
  const BBSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<BBSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final duration = BBMotion.of(context, BBMotion.standard);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bb.colors.surfaceSunken,
        borderRadius: BorderRadius.circular(BBRadius.badge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        // Labels wrap to two lines at large text; every segment then takes
        // the tallest one's height so the selected outline lines up.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in segments)
                Expanded(
                  child: Semantics(
                    selected: s.value == selected,
                    inMutuallyExclusiveGroup: true,
                    child: BBPressable(
                      semanticLabel: s.label,
                      // Tapping the selected segment is a no-op: no haptic, no callback.
                      haptic: s.value != selected,
                      onTap: () {
                        if (s.value != selected) onChanged(s.value);
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: AnimatedContainer(
                          duration: duration,
                          curve: BBMotion.curve,
                          padding: const EdgeInsets.symmetric(
                            vertical: BBSpace.s,
                          ),
                          decoration: BoxDecoration(
                            // Brand fill plus a brand border: the fill alone is ~1.3:1
                            // against the track, so the border carries the state
                            // (WCAG 1.4.11). Unselected segments keep a clear border
                            // of the same width so the row never shifts.
                            color: s.value == selected
                                ? bb.colors.brandSoft
                                : const Color(0x00000000),
                            border: Border.all(
                              color: s.value == selected
                                  ? bb.colors.brand
                                  : const Color(0x00000000),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            heightFactor: 1,
                            child: Text(
                              s.label,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: bb.text.label.copyWith(
                                color: s.value == selected
                                    ? bb.colors.brandInk
                                    : bb.colors.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

class BBSegment<T> {
  const BBSegment({required this.value, required this.label});
  final T value;
  final String label;
}

/// Segmented control: a field-surface track with one selection pill that slides to the chosen
/// segment over [BBMotion.standard] (spec §3.2), at once under Reduce Motion.
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

  static const pillKey = ValueKey('bb-segmented-pill');

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final duration = BBMotion.of(context, BBMotion.standard);
    final n = segments.length;
    final index = math.max(0, segments.indexWhere((s) => s.value == selected));
    return DecoratedBox(
      decoration: bb.field(radius: BBRadius.badge),
      child: Padding(
        padding: const EdgeInsets.all(3),
        // Labels wrap to two lines at large text; every segment then takes the tallest one's
        // height, and so does the pill.
        child: IntrinsicHeight(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedAlign(
                  key: pillKey,
                  duration: duration,
                  curve: BBMotion.curve,
                  alignment: Alignment(n <= 1 ? 0 : -1 + 2 * index / (n - 1), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    // Brand-soft fill plus a 1.5 px brandEdge border: the fill alone is ~1.3:1 against
                    // the track, so the edge carries the state (WCAG 1.4.11). brandEdge is brandInk in
                    // light, where bright green on white is under 3:1.
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: bb.colors.brandSoft,
                        border: Border.all(color: bb.brandEdge, width: 1.5),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: BBSpace.s, horizontal: 1.5),
                              child: Center(
                                heightFactor: 1,
                                child: Text(
                                  s.label,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: bb.text.label.copyWith(
                                    color: s.value == selected ? bb.colors.brandInk : bb.colors.muted,
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
            ],
          ),
        ),
      ),
    );
  }
}

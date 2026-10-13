import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'bb_icon_button.dart';
import 'bb_icons.dart';
import 'tokens.dart';

/// − value + stepper. Screen readers get one adjustable node
/// (swipe up/down to change).
class BBStepper extends StatelessWidget {
  const BBStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
    required this.format,
    required this.semanticLabel,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final String Function(int) format;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final canDec = value > min;
    final canInc = value < max;
    void dec() => onChanged(math.max(min, value - step));
    void inc() => onChanged(math.min(max, value + step));
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      value: format(value),
      increasedValue: canInc ? format(math.min(max, value + step)) : null,
      decreasedValue: canDec ? format(math.max(min, value - step)) : null,
      onIncrease: canInc ? inc : null,
      onDecrease: canDec ? dec : null,
      child: DecoratedBox(
        decoration: bb.field(radius: BBRadius.badge),
        child: Row(
          children: [
            BBIconButton(icon: BBIcons.remove, semanticLabel: 'Decrease $semanticLabel', onPressed: canDec ? dec : null),
            Expanded(
              child: ExcludeSemantics(
                child: Text(format(value), textAlign: TextAlign.center, style: bb.text.headline),
              ),
            ),
            BBIconButton(icon: BBIcons.add, semanticLabel: 'Increase $semanticLabel', onPressed: canInc ? inc : null),
          ],
        ),
      ),
    );
  }
}

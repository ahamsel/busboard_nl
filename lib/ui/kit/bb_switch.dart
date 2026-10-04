import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

class BBSwitch extends StatelessWidget {
  const BBSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    final duration = BBMotion.of(context, BBMotion.standard);
    final enabled = onChanged != null;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: enabled,
      onTap: enabled ? () => onChanged!(!value) : null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: duration,
            curve: BBMotion.curve,
            width: 46,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? c.brand : c.surfaceSunken,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: value ? c.brand : c.line),
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: BBMotion.curve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: value ? c.onBrand : c.surface, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

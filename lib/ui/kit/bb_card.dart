import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

class BBCard extends StatelessWidget {
  const BBCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: 10),
    this.semanticLabel,
    this.exposeSemantics = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  /// See [BBPressable.exposeSemantics].
  final bool exposeSemantics;

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: context.bb.card(),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) {
      return BBPressable(onTap: onTap, semanticLabel: semanticLabel, exposeSemantics: exposeSemantics, child: box);
    }
    if (semanticLabel != null) {
      return Semantics(label: semanticLabel, excludeSemantics: true, child: box);
    }
    return box;
  }
}

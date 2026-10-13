import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

/// Marks a sheet, panel or dialog. Cards inside one sit on `surface`, so they rise to
/// `surfaceRaised`, and chips use the field surface instead of floating (spec §2.1).
class BBSurfaceScope extends InheritedWidget {
  const BBSurfaceScope({super.key, required super.child});

  /// Whether [context] sits on a sheet, panel or dialog.
  static bool isRaised(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BBSurfaceScope>() != null;

  /// The card decoration for where [context] sits.
  static BoxDecoration cardOf(BuildContext context, {double radius = BBRadius.card}) =>
      context.bb.card(radius: radius, raised: isRaised(context));

  @override
  bool updateShouldNotify(BBSurfaceScope oldWidget) => false;
}

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
      decoration: BBSurfaceScope.cardOf(context),
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

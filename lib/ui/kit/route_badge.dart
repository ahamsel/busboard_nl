import 'package:flutter/widgets.dart';

import 'route_palette.dart';
import 'tokens.dart';

enum RouteBadgeSize { large, compact }

class RouteBadge extends StatelessWidget {
  const RouteBadge({
    super.key,
    required this.routeNumber,
    this.label,
    this.size = RouteBadgeSize.large,
  });

  final int routeNumber;

  /// Text shown in the badge; defaults to the route number.
  final String? label;
  final RouteBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fill = RoutePalette.of(routeNumber).fillFor(bb.brightness);
    final text = label ?? '$routeNumber';
    final large = size == RouteBadgeSize.large;
    final style = bb.text.label.copyWith(
      color: RoutePalette.ink,
      fontSize: large ? 17 : 12,
      fontWeight: FontWeight.w800,
    );

    final Widget badge = large
        ? SizedBox(
            width: 40,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(BBRadius.badge)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(text, style: style, maxLines: 1),
                ),
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(BBRadius.pill)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BBSpace.s, vertical: 3),
                child: Text(text, style: style, maxLines: 1, textAlign: TextAlign.center),
              ),
            ),
          );

    return Semantics(label: 'Route $text', excludeSemantics: true, child: badge);
  }
}

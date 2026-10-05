import 'package:flutter/widgets.dart';

import 'bb_route_dots.dart';
import 'tokens.dart';

/// Hopping route dots with an optional label, announced to screen readers.
/// For short inline waits; first loads of lists use [BBSkeleton].
class BBLoading extends StatelessWidget {
  const BBLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Semantics(
      label: label ?? 'Loading',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BBRouteDots(),
          if (label != null) ...[
            const SizedBox(height: BBSpace.m),
            ExcludeSemantics(
              child: Text(label!, textAlign: TextAlign.center, style: bb.text.body.copyWith(color: bb.colors.muted)),
            ),
          ],
        ],
      ),
    );
  }
}

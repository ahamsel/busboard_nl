import 'package:flutter/material.dart';

import 'tokens.dart';

/// Brand spinner with an optional label, announced to screen readers.
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
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: bb.colors.brand),
          ),
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

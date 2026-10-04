import 'package:flutter/material.dart';

import 'tokens.dart';

/// Pull to refresh with a brand-coloured indicator on a flat surface disc.
class BBRefresh extends StatelessWidget {
  const BBRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: c.brand,
      backgroundColor: c.surface,
      elevation: 0,
      displacement: 48,
      child: child,
    );
  }
}

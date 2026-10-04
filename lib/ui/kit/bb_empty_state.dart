import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum BBEmptyTone { neutral, error }

/// Centred icon + title + optional message and action, for empty and error
/// states.
class BBEmptyState extends StatelessWidget {
  const BBEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = BBEmptyTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final BBEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.all(BBSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: tone == BBEmptyTone.error ? bb.colors.dangerInk : bb.colors.muted),
          const SizedBox(height: BBSpace.m),
          Text(title, textAlign: TextAlign.center, style: bb.text.headline),
          if (message != null) ...[
            const SizedBox(height: BBSpace.xs),
            Text(message!, textAlign: TextAlign.center, style: bb.text.body.copyWith(color: bb.colors.muted)),
          ],
          if (action != null) ...[
            const SizedBox(height: BBSpace.l),
            action!,
          ],
        ],
      ),
    );
  }
}

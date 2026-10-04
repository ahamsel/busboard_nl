import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum BBPillTone { neutral, brand, live, warn, danger }

class BBPill extends StatelessWidget {
  const BBPill({
    super.key,
    required this.label,
    this.tone = BBPillTone.neutral,
    this.background,
    this.foreground,
    this.leadingDot = false,
  });

  final String label;
  final BBPillTone tone;

  /// Overrides the tone (used for route pills).
  final Color? background;
  final Color? foreground;
  final bool leadingDot;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    final (bg, fg) = switch (tone) {
      BBPillTone.neutral => (c.surfaceSunken, c.ink),
      BBPillTone.brand => (c.brandSoft, c.brandInk),
      BBPillTone.live => (c.liveSoft, c.liveInk),
      BBPillTone.warn => (c.warnBg, c.warnInk),
      BBPillTone.danger => (c.dangerBg, c.dangerInk),
    };
    final fgColor = foreground ?? fg;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? bg,
        borderRadius: BorderRadius.circular(BBRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BBSpace.s, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingDot) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: fgColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: context.bb.text.caption.copyWith(color: fgColor, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

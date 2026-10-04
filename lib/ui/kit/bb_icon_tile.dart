import 'package:flutter/widgets.dart';

import 'bb_pill.dart';
import 'tokens.dart';

/// Rounded tinted square holding an icon (list leading visual).
class BBIconTile extends StatelessWidget {
  const BBIconTile({super.key, required this.icon, this.tone = BBPillTone.brand, this.size = 40});

  final IconData icon;
  final BBPillTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    final (bg, fg) = switch (tone) {
      BBPillTone.neutral => (c.surfaceSunken, c.muted),
      BBPillTone.brand => (c.brandSoft, c.brandInk),
      BBPillTone.live => (c.liveSoft, c.liveInk),
      BBPillTone.warn => (c.warnBg, c.warnInk),
      BBPillTone.danger => (c.dangerBg, c.dangerInk),
    };
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(BBRadius.badge)),
          child: Icon(icon, size: size * 0.5, color: fg),
        ),
      ),
    );
  }
}

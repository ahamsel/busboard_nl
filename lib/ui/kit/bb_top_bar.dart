import 'package:flutter/widgets.dart';

import 'bb_icon_button.dart';
import 'bb_icons.dart';
import 'tokens.dart';

/// Page title bar: optional back button, title (+ subtitle) and trailing
/// actions. [large] uses the display style for root screens.
class BBTopBar extends StatelessWidget {
  const BBTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.large = false,
    this.condensed = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool large;

  /// Content has scrolled under the bar: a [large] title shrinks to the inline title (spec §5).
  final bool condensed;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.xs, BBSpace.s, BBSpace.xs, BBSpace.s),
      child: Row(
        children: [
          if (onBack != null)
            BBIconButton(icon: BBIcons.back, semanticLabel: 'Back', onPressed: onBack)
          else
            const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: AnimatedDefaultTextStyle(
                    duration: BBMotion.of(context, BBMotion.standard),
                    curve: BBMotion.curve,
                    style: large && !condensed ? bb.text.display : bb.text.title,
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: bb.text.caption),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

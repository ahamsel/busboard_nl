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
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool large;

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
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: large ? bb.text.display : bb.text.title,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.caption),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

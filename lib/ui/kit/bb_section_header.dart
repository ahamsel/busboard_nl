import 'package:flutter/widgets.dart';

import 'bb_pill.dart';
import 'tokens.dart';

class BBSectionHeader extends StatelessWidget {
  const BBSectionHeader({super.key, required this.title, this.count, this.countTone = BBPillTone.brand});

  final String title;
  final int? count;
  final BBPillTone countTone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Semantics(header: true, child: Text(title, style: context.bb.text.title)),
        ),
        if (count != null) ...[
          const SizedBox(width: BBSpace.s),
          BBPill(label: '$count', tone: countTone),
        ],
      ],
    );
  }
}

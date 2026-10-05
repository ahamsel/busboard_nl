import 'package:flutter/widgets.dart';

import 'tokens.dart';

class BBDivider extends StatelessWidget {
  const BBDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: context.bb.colors.line)),
    );
  }
}

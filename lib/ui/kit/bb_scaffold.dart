import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Page shell: `bg` background, top safe area, system-bar icon brightness
/// matching the theme, and a Material ancestor (kit-internal) so
/// [BBTextField] works.
class BBScaffold extends StatelessWidget {
  const BBScaffold({super.key, required this.body, this.safeTop = true});

  final Widget body;
  final bool safeTop;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final overlay = (bb.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: const Color(0x00000000),
      systemNavigationBarColor: const Color(0x00000000),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Material(
        color: bb.colors.bg,
        child: DefaultTextStyle(
          style: bb.text.body,
          child: SafeArea(top: safeTop, bottom: false, child: body),
        ),
      ),
    );
  }
}

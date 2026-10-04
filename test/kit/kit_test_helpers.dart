import 'dart:convert';

import 'package:busboard_nl/ui/kit/bb_theme.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Loads every font in FontManifest.json (Figtree + MaterialIcons) so goldens
/// render real glyphs instead of test boxes.
Future<void> loadAppFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// Hosts a kit widget in the real Harbour theme on a `bg`-coloured page.
Widget kitHost(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  double width = 390,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.dark ? BBTheme.dark() : BBTheme.light(),
    themeAnimationStyle: AnimationStyle.noAnimation,
    scrollBehavior: const BBScrollBehavior(),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Builder(
      // Deliberately no Material ancestor: kit widgets must supply their own
      // (BBScaffold / BBTextField), as they will in the real screens.
      builder: (context) => ColoredBox(
        color: context.bb.colors.bg,
        child: DefaultTextStyle(
          style: context.bb.text.body,
          child: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

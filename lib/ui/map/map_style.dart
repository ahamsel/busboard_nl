import 'package:flutter/widgets.dart';

import '../kit/kit.dart';

/// Which "Harbour quiet" style the map loads (spec §3.1): the app theme, or
/// the Settings → Map theme override (null or system = follow the app).
abstract final class MapStyle {
  static const lightAsset = 'assets/map/harbour_light.json';
  static const darkAsset = 'assets/map/harbour_dark.json';

  static Brightness brightnessFor(Brightness app, BBThemeMode? override) => switch (override) {
        BBThemeMode.light => Brightness.light,
        BBThemeMode.dark => Brightness.dark,
        _ => app,
      };

  static String assetFor(Brightness app, BBThemeMode? override) =>
      brightnessFor(app, override) == Brightness.dark ? darkAsset : lightAsset;
}

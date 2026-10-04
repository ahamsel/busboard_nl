import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Ten jellybean route hues (spec §4.2). `fill` is the badge/pill background
/// in light mode, `fillDark` in dark mode, `line` the route shape on the map.
enum RouteHue {
  red(Color(0xFFFFC9C2), Color(0xFFFFB3A8), Color(0xFFD63B3B)),
  orange(Color(0xFFFFD9B8), Color(0xFFFFC28F), Color(0xFFE07A1F)),
  yellow(Color(0xFFFBE7A6), Color(0xFFF5D97A), Color(0xFFC9A219)),
  lime(Color(0xFFE2F0B0), Color(0xFFCFE58A), Color(0xFF7FA31F)),
  green(Color(0xFFCFEEDB), Color(0xFFA6E3BF), Color(0xFF2E9E62)),
  teal(Color(0xFFC4ECE8), Color(0xFF93DDD6), Color(0xFF1F8F86)),
  sky(Color(0xFFCFE3FA), Color(0xFFA9CDF5), Color(0xFF3E7CB1)),
  indigo(Color(0xFFD6DAFA), Color(0xFFB3BAF5), Color(0xFF4A57C9)),
  lilac(Color(0xFFE3D6FA), Color(0xFFCDB6F5), Color(0xFF8656D1)),
  pink(Color(0xFFFAD3E4), Color(0xFFF5B0CD), Color(0xFFC9417E));

  const RouteHue(this.fill, this.fillDark, this.line);

  final Color fill;
  final Color fillDark;
  final Color line;

  Color fillFor(Brightness brightness) =>
      brightness == Brightness.dark ? fillDark : fill;
}

/// The same route always gets the same colour everywhere in the app.
abstract final class RoutePalette {
  /// Text/number colour on every route fill, in both modes.
  static const Color ink = Color(0xFF1C2A3A);

  /// Hand-assigned from GTFS stop overlap so routes sharing stops differ.
  static const Map<int, RouteHue> assigned = {
    1: RouteHue.orange,
    2: RouteHue.red,
    3: RouteHue.yellow,
    6: RouteHue.teal,
    9: RouteHue.teal,
    10: RouteHue.green,
    11: RouteHue.teal,
    12: RouteHue.pink,
    13: RouteHue.indigo,
    14: RouteHue.red,
    15: RouteHue.lilac,
    16: RouteHue.yellow,
    18: RouteHue.lilac,
    19: RouteHue.sky,
    20: RouteHue.red,
    21: RouteHue.lime,
    22: RouteHue.green,
    23: RouteHue.lime,
    24: RouteHue.orange,
    26: RouteHue.pink,
    29: RouteHue.sky,
    30: RouteHue.orange,
  };

  /// Routes not in [assigned] (e.g. a newly added route) get a deterministic
  /// hue from their number.
  static RouteHue of(int routeNumber) =>
      assigned[routeNumber] ??
      RouteHue.values[routeNumber.abs() % RouteHue.values.length];
}

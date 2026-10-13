import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Ten jellybean route hues (spec §4.2). `fill` is the badge/pill background
/// in light mode, `fillDark` in dark mode, `line` the route shape on the light
/// map and `lineDark` on the dark map (the same colour wherever `line` already
/// reads at 3:1 on the dark land, otherwise a lighter shade of the hue).
enum RouteHue {
  red(Color(0xFFFFC9C2), Color(0xFFFFB3A8), Color(0xFFD63B3B)),
  orange(Color(0xFFFFD9B8), Color(0xFFFFC28F), Color(0xFFE07A1F)),
  yellow(Color(0xFFFBE7A6), Color(0xFFF5D97A), Color(0xFFC9A219)),
  // Was lime: too close to the brand green (spec §2.3).
  olive(Color(0xFFE8EBB8), Color(0xFFD8DE8F), Color(0xFF7C8A1C)),
  // Was green: blended into the brand and live greens (spec §2.3).
  ocean(Color(0xFFB9DDF0), Color(0xFF8FC6E6), Color(0xFF2D7BB2)),
  teal(Color(0xFFC4ECE8), Color(0xFF93DDD6), Color(0xFF1F8F86)),
  sky(Color(0xFFCFE3FA), Color(0xFFA9CDF5), Color(0xFF65ADE0)),
  // Lines moved away from the indigo accent. The dark-map line is lighter (#2E4E99 is 2.2:1 on the dark land) and
  // pushed a little toward violet so it stays clear of ocean.
  indigo(Color(0xFFD6DAFA), Color(0xFFB3BAF5), Color(0xFF2E4E99), Color(0xFF5673F0)),
  lilac(Color(0xFFE3D6FA), Color(0xFFCDB6F5), Color(0xFFA855C7)),
  pink(Color(0xFFFAD3E4), Color(0xFFF5B0CD), Color(0xFFC9417E));

  const RouteHue(this.fill, this.fillDark, this.line, [Color? lineDark]) : lineDark = lineDark ?? line;

  final Color fill;
  final Color fillDark;
  final Color line;
  final Color lineDark;

  Color fillFor(Brightness brightness) =>
      brightness == Brightness.dark ? fillDark : fill;

  /// The route's line on a map of the given brightness.
  Color lineFor(Brightness brightness) =>
      brightness == Brightness.dark ? lineDark : line;
}

/// The same route always gets the same colour everywhere in the app.
abstract final class RoutePalette {
  /// Text/number colour on every route fill, in both modes.
  static const Color ink = Color(0xFF13261A);

  /// Hand-assigned from GTFS stop overlap so routes sharing stops differ.
  static const Map<int, RouteHue> assigned = {
    1: RouteHue.orange,
    2: RouteHue.red,
    3: RouteHue.yellow,
    6: RouteHue.teal,
    9: RouteHue.teal,
    10: RouteHue.ocean,
    11: RouteHue.teal,
    12: RouteHue.pink,
    13: RouteHue.indigo,
    14: RouteHue.red,
    15: RouteHue.lilac,
    16: RouteHue.yellow,
    18: RouteHue.lilac,
    19: RouteHue.sky,
    20: RouteHue.red,
    21: RouteHue.olive,
    22: RouteHue.ocean,
    23: RouteHue.olive,
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

  /// Colour for a route's `route_short_name`. Plain numbers use [of]; anything
  /// else (e.g. "10A") gets a stable hue from a deterministic hash, so
  /// non-numeric routes do not all collapse onto one colour.
  static RouteHue ofName(String shortName) {
    final name = shortName.trim();
    if (name.isNotEmpty && _digitsOnly.hasMatch(name)) {
      final n = int.tryParse(name);
      if (n != null) return of(n);
    }
    return RouteHue.values[_stableHash(name) % RouteHue.values.length];
  }

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  /// Deterministic across runs and platforms (unlike `String.hashCode`):
  /// a 31-multiplier polynomial over the code units, masked to 31 bits.
  static int _stableHash(String s) {
    var h = 0;
    for (final unit in s.codeUnits) {
      h = (h * 31 + unit) & 0x7FFFFFFF;
    }
    return h;
  }
}

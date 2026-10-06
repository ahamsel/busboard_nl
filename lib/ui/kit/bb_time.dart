import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// The one clock format for every time the app shows: 24-hour ("16:05") or
/// 12-hour ("4:05 PM"), following the device's setting. Pure helpers take
/// [use24h]; widgets pass [BBTime.use24h] of their context.
abstract final class BBTime {
  /// The device's 24-hour clock setting.
  static bool use24h(BuildContext context) => MediaQuery.alwaysUse24HourFormatOf(context);

  /// A time of day from seconds since midnight; GTFS times past 24:00 wrap.
  static String clock(int secondsOfDay, {required bool use24h, bool seconds = false}) {
    final s = secondsOfDay % 86400;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    String two(int v) => v.toString().padLeft(2, '0');
    final sec = seconds ? ':${two(s % 60)}' : '';
    if (use24h) return '${two(h)}:${two(m)}$sec';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${two(m)}$sec ${h < 12 ? 'AM' : 'PM'}';
  }

  /// The time of day of [t].
  static String of(DateTime t, {required bool use24h, bool seconds = false}) =>
      clock(t.hour * 3600 + t.minute * 60 + t.second, use24h: use24h, seconds: seconds);

  /// "Nov 1, 12:44 PM"; with [year], "Nov 1, 2026 12:44 PM".
  static String dated(DateTime t, {required bool use24h, bool year = false}) =>
      '${DateFormat(year ? 'MMM d, yyyy' : 'MMM d,').format(t)} ${of(t, use24h: use24h)}';
}

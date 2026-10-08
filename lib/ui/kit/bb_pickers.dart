import 'package:flutter/material.dart';

/// The system clock dialog (kit-only Material), to the minute. Returns [initial]'s day at the picked time, or
/// null when the rider cancels.
Future<DateTime?> showBBTimePicker(BuildContext context, {required DateTime initial}) async {
  final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (picked == null) return null;
  return DateTime(initial.year, initial.month, initial.day, picked.hour, picked.minute);
}

/// The system calendar dialog (kit-only Material), from [first] to [last] (dates only). Returns the picked day
/// at [initial]'s time of day, or null when the rider cancels.
Future<DateTime?> showBBDatePicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) async {
  DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
  final lo = day(first);
  final hi = day(last).isBefore(lo) ? lo : day(last);
  var start = day(initial);
  if (start.isBefore(lo)) start = lo;
  if (start.isAfter(hi)) start = hi;
  final picked = await showDatePicker(context: context, initialDate: start, firstDate: lo, lastDate: hi);
  if (picked == null) return null;
  return DateTime(picked.year, picked.month, picked.day, initial.hour, initial.minute);
}

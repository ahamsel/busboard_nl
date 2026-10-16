import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/arrival/first_bus.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';

/// What a stop with no bus due says when service has ended: its first bus, from the loaded schedule.
class FirstBusNote {
  const FirstBusNote({required this.text, required this.spoken});

  /// "First bus 6:30 AM", or "First bus Mon 6:28 AM" when it is days away.
  final String text;

  /// [text] for a screen reader: the weekday in full ("Monday").
  final String spoken;
}

/// The first-bus note for [stopId] at the planner clock's now, or null when the next departure is a later one of its
/// day (a gap in the day), nothing leaves the stop in the next 7 days, or the schedule is not loaded: the caller keeps
/// its plain empty text. The Board's empty state and the stop cards share it, so they never disagree.
FirstBusNote? firstBusNoteFor(WidgetRef ref, String stopId, {required bool use24h}) {
  final repo = ref.watch(gtfsRepositoryProvider).value;
  if (repo == null) return null;
  final now = ref.read(plannerClockProvider)();
  final first = firstBusAfter(repo, stopId, now);
  if (first == null) return null;
  return FirstBusNote(
    text: firstBusNote(first, now, use24h: use24h),
    spoken: firstBusNote(first, now, use24h: use24h, spoken: true),
  );
}

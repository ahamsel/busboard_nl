import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trip_planner/saved_place_store.dart';
import '../domain/trip_planner/place.dart';
import 'home_tab_provider.dart';
import 'providers.dart';
import 'recent_stops_provider.dart';
import 'saved_place_providers.dart';

/// What a Board stop chip stands for (spec 2026-10-15 §3).
enum BoardChipKind { yours, saved, recent }

/// One of the Board's stop chips: [stopId], and for a saved place the [place] it was saved as (its name and icon).
@immutable
class BoardChip {
  const BoardChip(this.kind, this.stopId, {this.place});
  final BoardChipKind kind;
  final String stopId;
  final SavedPlace? place;

  @override
  bool operator ==(Object other) =>
      other is BoardChip && other.kind == kind && other.stopId == stopId && other.place?.id == place?.id;
  @override
  int get hashCode => Object.hash(kind, stopId, place?.id);
  @override
  String toString() => 'BoardChip(${kind.name}, $stopId)';
}

/// The most recently viewed stops the Board shows as chips.
const maxRecentChips = 3;

/// The Board's stop chips in order: your stop, then saved places that are stops, then up to [maxRecentChips] recently
/// viewed stops (newest first). Each stop has one chip, the first it earns. Near me and ＋ always follow them.
List<BoardChip> boardStopChips({
  String? yourStopId,
  List<SavedPlace> saved = const [],
  List<String> recent = const [],
}) {
  // Elements are built in order, so by the recents every stop chip before them is in [seen].
  final seen = <String>{};
  return [
    if (yourStopId != null && seen.add(yourStopId)) BoardChip(BoardChipKind.yours, yourStopId),
    for (final p in saved)
      if (p.place case StopPlace(:final stopId) when seen.add(stopId)) BoardChip(BoardChipKind.saved, stopId, place: p),
    ...[
      for (final id in recent)
        if (seen.add(id)) BoardChip(BoardChipKind.recent, id),
    ].take(maxRecentChips),
  ];
}

/// The Board's stop chips for the rider's stop, saved places and recent stops. Only stops in the loaded schedule get
/// one (a stop a later schedule removed, still in the recents or the settings, would show as "Stop 1234" and an empty
/// board); until the schedule is loaded there are none.
final boardChipsProvider = Provider<List<BoardChip>>((ref) {
  final stops = ref.watch(gtfsRepositoryProvider).asData?.value.stopsById;
  bool known(String id) => stops != null && stops.containsKey(id);
  final mine = ref.watch(settingsProvider.select((s) => s.selectedStopId));
  return boardStopChips(
    yourStopId: mine != null && known(mine) ? mine : null,
    saved: [
      for (final p in ref.watch(savedPlacesProvider).value ?? const <SavedPlace>[])
        if (p.place is! StopPlace || known((p.place as StopPlace).stopId)) p,
    ],
    // Filtered before the first few are taken, so the unknown ones do not use up the row.
    recent: [
      for (final id in ref.watch(recentStopsProvider).value ?? const <String>[])
        if (known(id)) id,
    ],
  );
});

/// The stop the Board shows: the one picked, else your stop, else the first saved place that is a stop. Your stop and
/// the saved ones count only if the loaded schedule has them, as with the chips (a stop a later schedule removed would
/// show as "Stop 1234" and an empty board); while the schedule is still loading, or failed to, there is nothing to check
/// against and they are taken as they are, so the Board shows its stop (with its error state) rather than "Choose your
/// stop". Null when there is none: the Board asks you to choose your stop.
final boardShownStopProvider = Provider<BoardStop?>((ref) {
  final picked = ref.watch(boardStopProvider);
  if (picked != null) return picked;
  // A schedule that has not loaded (yet, or at all) says nothing against a stop: it is skipped only when a loaded
  // schedule lacks it. `value` keeps the last schedule through an error.
  final stops = ref.watch(gtfsRepositoryProvider).value?.stopsById;
  bool known(String id) => stops?.containsKey(id) ?? true;
  final mine = ref.watch(settingsProvider.select((s) => s.selectedStopId));
  if (mine != null && known(mine)) return BoardStop(mine);
  for (final p in ref.watch(savedPlacesProvider).value ?? const <SavedPlace>[]) {
    if (p.place case StopPlace(:final stopId) when known(stopId)) return BoardStop(stopId);
  }
  return null;
});

/// Your stop and your saved places have been read from the phone. Until then "no stop" may only mean "not read yet",
/// so the Board shows neither its empty state nor a nearby-stops list that would ask for the location.
final boardReadyProvider = Provider<bool>(
  (ref) => !ref.watch(settingsLoadedProvider).isLoading && !ref.watch(savedPlacesProvider).isLoading,
);

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

/// The Board's stop chips for the rider's stop, saved places and recent stops.
final boardChipsProvider = Provider<List<BoardChip>>(
  (ref) => boardStopChips(
    yourStopId: ref.watch(settingsProvider.select((s) => s.selectedStopId)),
    saved: ref.watch(savedPlacesProvider).value ?? const [],
    recent: ref.watch(recentStopsProvider).value ?? const [],
  ),
);

/// The stop the Board shows: the one picked, else your stop, else the first saved place that is a stop. Null when
/// there is none: the Board asks you to choose your stop.
final boardShownStopProvider = Provider<BoardStop?>((ref) {
  final picked = ref.watch(boardStopProvider);
  if (picked != null) return picked;
  final mine = ref.watch(settingsProvider.select((s) => s.selectedStopId));
  if (mine != null) return BoardStop(mine);
  for (final p in ref.watch(savedPlacesProvider).value ?? const <SavedPlace>[]) {
    if (p.place case StopPlace(:final stopId)) return BoardStop(stopId);
  }
  return null;
});

/// Your stop and your saved places have been read from the phone. Until then "no stop" may only mean "not read yet",
/// so the Board shows neither its empty state nor a nearby-stops list that would ask for the location.
final boardReadyProvider = Provider<bool>(
  (ref) => !ref.watch(settingsLoadedProvider).isLoading && !ref.watch(savedPlacesProvider).isLoading,
);

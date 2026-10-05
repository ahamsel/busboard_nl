import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime/metrobus_mobile_api.dart';
import '../data/realtime/timetrack_models.dart';
import '../domain/arrival/arrival_models.dart';
import '../domain/arrival/arrival_service.dart';
import 'providers.dart';

/// What the map sheet shows besides your stop: a tapped stop or a tapped bus.
sealed class MapSelection {
  const MapSelection();
}

class StopSelection extends MapSelection {
  const StopSelection(this.stopId);
  final String stopId;

  @override
  bool operator ==(Object other) => other is StopSelection && other.stopId == stopId;
  @override
  int get hashCode => Object.hash(StopSelection, stopId);
}

class BusSelection extends MapSelection {
  const BusSelection(this.vehicleId);
  final String vehicleId;

  @override
  bool operator ==(Object other) => other is BusSelection && other.vehicleId == vehicleId;
  @override
  int get hashCode => Object.hash(BusSelection, vehicleId);
}

class MapSelectionNotifier extends Notifier<MapSelection?> {
  @override
  MapSelection? build() => null;

  void select(MapSelection? selection) => state = selection;
  void clear() => state = null;
}

final mapSelectionProvider = NotifierProvider<MapSelectionNotifier, MapSelection?>(MapSelectionNotifier.new);

/// Routes shown on the map. Empty = every route (spec §3.3).
class RouteFilterNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void toggle(int route) {
    final next = {...state};
    if (!next.remove(route)) next.add(route);
    state = Set.unmodifiable(next);
  }

  void showAll() => state = const {};
}

final mapRouteFilterProvider = NotifierProvider<RouteFilterNotifier, Set<int>>(RouteFilterNotifier.new);

/// Upcoming arrivals at any stop (the map's stop card and your-stop peek), from
/// the schedule, the live vehicle feed and the stop-prediction feed. Re-fetches
/// every refresh interval while something watches it.
final stopArrivalsProvider = FutureProvider.autoDispose.family<List<ArrivalRow>, String>((ref, stopId) async {
  final repo = ref.watch(gtfsRepositoryProvider).value;
  if (repo == null) return const [];
  final seconds = ref.watch(settingsProvider.select((s) => s.refreshIntervalSeconds));
  final timer = Timer(Duration(seconds: seconds), ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  List<TimeTrackVehicle>? liveVehicles;
  try {
    final result = await ref.read(timetrackApiProvider).fetchVehiclesResult();
    if (result.succeeded) liveVehicles = result.vehicles;
  } catch (_) {
    // Schedule only.
  }
  List<MetrobusDeparture>? stopPredictions;
  try {
    stopPredictions = (await ref.read(metrobusMobileApiProvider).fetchDeparturesResult(stopId)).departures;
  } catch (_) {
    // Schedule and live vehicles only.
  }
  return ArrivalService(repo).getUpcomingArrivals(
    stopId: stopId,
    now: DateTime.now(),
    liveVehicles: liveVehicles,
    stopPredictions: stopPredictions,
  );
});

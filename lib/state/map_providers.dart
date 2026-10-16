import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
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

/// The map's frame clock. Tests move it (an app pause of several minutes).
final mapClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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

/// Whether the app is on screen (resumed). Polling providers pause while it is
/// not, like the board does.
class AppForegroundNotifier extends Notifier<bool> with WidgetsBindingObserver {
  @override
  bool build() {
    final binding = WidgetsBinding.instance..addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    final lifecycle = binding.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => setForeground(state == AppLifecycleState.resumed);

  void setForeground(bool foreground) => state = foreground;
}

final appForegroundProvider = NotifierProvider<AppForegroundNotifier, bool>(AppForegroundNotifier.new);

/// Upcoming arrivals at any stop (the map's stop card and your-stop peek), from
/// the schedule, the live vehicle feed and the stop-prediction feed. Re-fetches
/// every refresh interval while something watches it and the app is in the
/// foreground; coming back to the foreground fetches once and resumes polling.
///
/// Loading until the schedule is first loaded (each launch parses it, and a first install downloads it first), and an
/// error if that first load fails: never an empty list then, which would read as "No buses due soon". A schedule
/// loaded once is used from then on, even when a reload fails (Refresh schedule, offline).
final stopArrivalsProvider = FutureProvider.autoDispose.family<List<ArrivalRow>, String>((ref, stopId) async {
  // The schedule already loaded, if any (kept through a failed reload); else the first load, waited for below. Only
  // the future is watched (a reload starts a new one): watching the state too would run a second fetch as the first
  // load lands, beside the one already waiting for it.
  final load = ref.watch(gtfsRepositoryProvider.future);
  final loaded = ref.read(gtfsRepositoryProvider);
  final schedule = loaded.hasValue ? Future.value(loaded.requireValue) : load;
  final seconds = ref.watch(settingsProvider.select((s) => s.refreshIntervalSeconds));
  // Your stop's arrivals outlive their last listener (a bus card replaces the
  // your-stop card for a while): coming back shows them at once, no skeleton.
  // The link is closed when the selection moves to another stop.
  final selectedStopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
  if (selectedStopId == stopId) ref.keepAlive();

  // Nobody watching (kept alive only): do not poll; refresh once on return.
  var watched = true;
  var stale = false;
  ref.onCancel(() => watched = false);
  ref.onResume(() {
    watched = true;
    // Invalidating from inside the resume callback itself had no effect.
    if (stale) scheduleMicrotask(() => ref.mounted ? ref.invalidateSelf() : null);
  });
  void refreshWhenWatched() {
    if (watched) {
      ref.invalidateSelf();
    } else {
      stale = true;
    }
  }

  // Background: no timer. Foreground again: refresh now, which re-arms it.
  ref.listen(appForegroundProvider, (_, foreground) {
    if (foreground) refreshWhenWatched();
  });

  // The next poll is armed once this fetch is over: a fetch slower than the interval (the live client waits up
  // to 10 s a feed) would otherwise be restarted before it could ever finish, and the rider would see no rows.
  void armPoll() {
    if (!ref.mounted || !ref.read(appForegroundProvider)) return;
    final timer = Timer(Duration(seconds: seconds), () {
      if (ref.read(appForegroundProvider)) refreshWhenWatched();
    });
    ref.onDispose(timer.cancel);
  }

  try {
    final repo = await schedule;
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
  } finally {
    armPoll();
  }
});

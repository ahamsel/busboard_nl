import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime/metrobus_mobile_api.dart';
import '../data/realtime/timetrack_models.dart';
import '../domain/arrival/arrival_models.dart';
import '../domain/arrival/arrival_service.dart';
import 'providers.dart';

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
final stopArrivalsProvider = FutureProvider.autoDispose.family<List<ArrivalRow>, String>((ref, stopId) async {
  final repo = ref.watch(gtfsRepositoryProvider).value;
  if (repo == null) return const [];
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
    final now = DateTime.now();
    final rows = ArrivalService(repo).getUpcomingArrivals(
      stopId: stopId,
      now: now,
      liveVehicles: liveVehicles,
      stopPredictions: stopPredictions,
    );
    if (ref.mounted) ref.read(stopArrivalsUpdatedAtProvider.notifier).stamp(stopId, now);
    return rows;
  } finally {
    armPoll();
  }
});

/// When each stop's arrivals were last loaded (the sheet's "updated" time). Set by [stopArrivalsProvider] as a
/// load completes, so callers of that provider need not change.
class StopArrivalsUpdatedAtNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() => const {};

  void stamp(String stopId, DateTime at) => state = {...state, stopId: at};
}

final stopArrivalsUpdatedAtProvider =
    NotifierProvider<StopArrivalsUpdatedAtNotifier, Map<String, DateTime>>(StopArrivalsUpdatedAtNotifier.new);

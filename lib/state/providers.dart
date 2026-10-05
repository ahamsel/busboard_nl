import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/gtfs/gtfs_models.dart';
import '../data/gtfs/gtfs_repository.dart';
import '../data/realtime/metrobus_mobile_api.dart';
import '../data/realtime/service_alert_models.dart';
import '../data/realtime/service_alerts_api.dart';
import '../data/realtime/timetrack_api.dart';
import '../data/realtime/timetrack_models.dart';
import '../domain/arrival/arrival_models.dart';
import '../domain/arrival/arrival_service.dart';
import '../domain/location/nearest_stop_service.dart';
import '../domain/map/bus_track_store.dart';
import '../domain/map/delayed_track_renderer.dart';
import '../domain/map/route_geometry.dart';
import '../domain/map/bus_tracking_state.dart';

// ─── Settings ──────────────────────────────────────────────

class AppSettings {
  final String? selectedStopId;
  final int refreshIntervalSeconds;
  final DateTime? lastGtfsUpdate;
  final bool forceGtfsRefresh;
  final ThemeMode themeMode;
  final ThemeMode? mapThemeMode; // null = follow app theme

  const AppSettings({
    this.selectedStopId,
    this.refreshIntervalSeconds = 5,
    this.lastGtfsUpdate,
    this.forceGtfsRefresh = false,
    this.themeMode = ThemeMode.system,
    this.mapThemeMode,
  });

  AppSettings copyWith({
    String? selectedStopId,
    int? refreshIntervalSeconds,
    DateTime? lastGtfsUpdate,
    bool? forceGtfsRefresh,
    ThemeMode? themeMode,
    ThemeMode? mapThemeMode,
  }) {
    return AppSettings(
      selectedStopId: selectedStopId ?? this.selectedStopId,
      refreshIntervalSeconds:
          refreshIntervalSeconds ?? this.refreshIntervalSeconds,
      lastGtfsUpdate: lastGtfsUpdate ?? this.lastGtfsUpdate,
      forceGtfsRefresh: forceGtfsRefresh ?? this.forceGtfsRefresh,
      themeMode: themeMode ?? this.themeMode,
      mapThemeMode: mapThemeMode ?? this.mapThemeMode,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _loadFromPrefs();
    return const AppSettings();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      selectedStopId: prefs.getString('selectedStopId'),
      // Keep the stored value inside the 5..60 s range the UI offers.
      refreshIntervalSeconds: (prefs.getInt('refreshInterval') ?? 5).clamp(5, 60),
      lastGtfsUpdate: prefs.getString('lastGtfsUpdate') != null
          ? DateTime.tryParse(prefs.getString('lastGtfsUpdate')!)
          : null,
      themeMode: ThemeMode.values[prefs.getInt('themeMode') ?? 0],
      mapThemeMode: prefs.getInt('mapThemeMode') != null
          ? ThemeMode.values[prefs.getInt('mapThemeMode')!]
          : null,
    );
  }

  Future<void> setSelectedStop(String stopId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedStopId', stopId);
    state = state.copyWith(selectedStopId: stopId);
  }

  Future<void> setRefreshInterval(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('refreshInterval', seconds);
    state = state.copyWith(refreshIntervalSeconds: seconds);
  }

  Future<void> setLastGtfsUpdate(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastGtfsUpdate', time.toIso8601String());
    state = state.copyWith(lastGtfsUpdate: time);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setMapThemeMode(ThemeMode? mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode == null) {
      await prefs.remove('mapThemeMode');
    } else {
      await prefs.setInt('mapThemeMode', mode.index);
    }
    // Manually construct to allow setting null (copyWith ?? prevents null)
    state = AppSettings(
      selectedStopId: state.selectedStopId,
      refreshIntervalSeconds: state.refreshIntervalSeconds,
      lastGtfsUpdate: state.lastGtfsUpdate,
      forceGtfsRefresh: state.forceGtfsRefresh,
      themeMode: state.themeMode,
      mapThemeMode: mode,
    );
  }

  void requestForceRefresh() {
    state = state.copyWith(forceGtfsRefresh: true);
  }

  void clearForceRefresh() {
    state = state.copyWith(forceGtfsRefresh: false);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// ─── GTFS Repository ───────────────────────────────────────

final gtfsRepositoryProvider = FutureProvider<GtfsRepository>((ref) async {
  final settings = ref.read(settingsProvider);
  final force = settings.forceGtfsRefresh;

  final repo = GtfsRepository();
  await repo.load(force: force);

  // Update settings after build is complete
  Future.microtask(() {
    if (force) {
      ref.read(settingsProvider.notifier).clearForceRefresh();
    }
    final lastDownload = repo.lastDownloadTime();
    lastDownload.then((time) {
      if (time != null) {
        ref.read(settingsProvider.notifier).setLastGtfsUpdate(time);
      }
    });
  });

  return repo;
});

// ─── Metrobus Stop Predictions ────────────────────────────

final metrobusMobileApiProvider = Provider<MetrobusMobileApi>((ref) {
  final api = MetrobusMobileApi();
  ref.onDispose(() => api.dispose());
  return api;
});

// ─── Service Alerts + Network Status ─────────────────────

final serviceAlertsApiProvider = Provider<ServiceAlertsApi>((ref) {
  final api = ServiceAlertsApi();
  ref.onDispose(api.dispose);
  return api;
});

final serviceUpdatesProvider = StreamProvider<ServiceUpdates>((ref) {
  final api = ref.watch(serviceAlertsApiProvider);
  final controller = StreamController<ServiceUpdates>();
  var disposed = false;

  Future<void> refresh() async {
    try {
      final updates = await api.fetchUpdates();
      if (!disposed) controller.add(updates);
    } catch (error, stackTrace) {
      // A transient outage should surface as an error but must not terminate
      // the polling stream; the next minute gets another clean attempt.
      if (!disposed) controller.addError(error, stackTrace);
    }
  }

  unawaited(refresh());
  final timer = Timer.periodic(
    const Duration(seconds: 60),
    (_) => unawaited(refresh()),
  );
  ref.onDispose(() {
    disposed = true;
    timer.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});

// ─── TimeTrack Live Data ───────────────────────────────────

final timetrackApiProvider = Provider<TimeTrackApi>((ref) {
  final api = TimeTrackApi();
  ref.onDispose(() => api.dispose());
  return api;
});

final timetrackVehiclesProvider = FutureProvider<List<TimeTrackVehicle>>((
  ref,
) async {
  final api = ref.read(timetrackApiProvider);
  return api.fetchVehicles();
});

// ─── Arrivals for selected stop ────────────────────────────

final arrivalsProvider = FutureProvider.autoDispose<List<ArrivalRow>>((
  ref,
) async {
  final settings = ref.watch(settingsProvider);
  final stopId = settings.selectedStopId;
  if (stopId == null) return [];

  final repoAsync = ref.watch(gtfsRepositoryProvider);
  final repo = repoAsync.asData?.value;
  if (repo == null) return [];

  final service = ArrivalService(repo);

  // Try to get live vehicles
  List<TimeTrackVehicle>? liveVehicles;
  try {
    final api = ref.read(timetrackApiProvider);
    final result = await api.fetchVehiclesResult();
    if (result.succeeded) {
      liveVehicles = result.vehicles;
    }
  } catch (_) {
    // Live data unavailable — continue with schedule only
  }

  return service.getUpcomingArrivals(
    stopId: stopId,
    now: DateTime.now(),
    liveVehicles: liveVehicles,
  );
});

// ─── Nearest Stops ─────────────────────────────────────────

final nearestStopServiceProvider = Provider<NearestStopService>((ref) {
  return NearestStopService();
});

final nearestStopsProvider = FutureProvider.autoDispose<List<NearbyStop>>((
  ref,
) async {
  final repoAsync = ref.watch(gtfsRepositoryProvider);
  final repo = repoAsync.asData?.value;
  if (repo == null) return [];

  final service = ref.read(nearestStopServiceProvider);

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return [];
    }
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );

  return service.findNearestStops(
    latitude: position.latitude,
    longitude: position.longitude,
    allStops: repo.stopsById.values,
  );
});

// ─── Bus motion (spec §3.4) ───────────────────────────────

final routeGeometryProvider = Provider<RouteGeometry?>((ref) {
  final repo = ref.watch(gtfsRepositoryProvider).asData?.value;
  return repo == null ? null : RouteGeometry(repo);
});

final busTrackStoreProvider = Provider<BusTrackStore?>((ref) {
  final geometry = ref.watch(routeGeometryProvider);
  return geometry == null ? null : BusTrackStore(geometry);
});

final busTrackRendererProvider = Provider<DelayedTrackRenderer?>((ref) {
  final geometry = ref.watch(routeGeometryProvider);
  return geometry == null ? null : DelayedTrackRenderer(geometry);
});

/// Polls the live feed into [busTrackStoreProvider] and publishes one
/// [BusTrackingState] per bus after every poll.
final busTrackingStreamProvider = StreamProvider<Map<String, BusTrackingState>>((ref) async* {
  final store = ref.watch(busTrackStoreProvider);
  if (store == null) {
    yield const {};
    return;
  }
  final api = ref.read(timetrackApiProvider);
  final interval = Duration(seconds: ref.watch(settingsProvider.select((s) => s.refreshIntervalSeconds)));

  Map<String, BusTrackingState> snapshot(DateTime now) => Map.unmodifiable({
        for (final t in store.tracks.values) t.vehicleId: BusTrackingState.fromTrack(t, stale: store.isStale(t, now)),
      });

  Future<void> poll() async {
    final now = DateTime.now();
    final result = await api.fetchVehiclesResult();
    if (result.succeeded) {
      store.ingest(result.vehicles, now);
    } else if (kDebugMode) {
      debugPrint('[Map] Live-data poll failed: ${result.error}');
    }
  }

  await poll();
  yield snapshot(DateTime.now());
  await for (final _ in Stream.periodic(interval)) {
    try {
      await poll();
      yield snapshot(DateTime.now());
    } catch (e) {
      if (kDebugMode) debugPrint('[Map] Live-data poll error: $e');
    }
  }
});

// ─── Stop Info helper ──────────────────────────────────────

final stopInfoProvider = Provider.family<StopInfo?, String>((ref, stopId) {
  final repoAsync = ref.watch(gtfsRepositoryProvider);
  final repo = repoAsync.asData?.value;
  return repo?.stopsById[stopId];
});

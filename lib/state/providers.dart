import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/gtfs/gtfs_models.dart';
import '../data/gtfs/gtfs_repository.dart';
import '../data/realtime/timetrack_api.dart';
import '../data/realtime/timetrack_models.dart';
import '../domain/arrival/arrival_models.dart';
import '../domain/arrival/arrival_service.dart';
import '../domain/location/nearest_stop_service.dart';

// ─── Settings ──────────────────────────────────────────────

class AppSettings {
  final String? selectedStopId;
  final int refreshIntervalSeconds;
  final DateTime? lastGtfsUpdate;
  final bool forceGtfsRefresh;

  const AppSettings({
    this.selectedStopId,
    this.refreshIntervalSeconds = 30,
    this.lastGtfsUpdate,
    this.forceGtfsRefresh = false,
  });

  AppSettings copyWith({
    String? selectedStopId,
    int? refreshIntervalSeconds,
    DateTime? lastGtfsUpdate,
    bool? forceGtfsRefresh,
  }) {
    return AppSettings(
      selectedStopId: selectedStopId ?? this.selectedStopId,
      refreshIntervalSeconds:
          refreshIntervalSeconds ?? this.refreshIntervalSeconds,
      lastGtfsUpdate: lastGtfsUpdate ?? this.lastGtfsUpdate,
      forceGtfsRefresh: forceGtfsRefresh ?? this.forceGtfsRefresh,
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
      refreshIntervalSeconds: prefs.getInt('refreshInterval') ?? 30,
      lastGtfsUpdate: prefs.getString('lastGtfsUpdate') != null
          ? DateTime.tryParse(prefs.getString('lastGtfsUpdate')!)
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
    liveVehicles = await api.fetchVehicles();
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

// ─── Stop Info helper ──────────────────────────────────────

final stopInfoProvider = Provider.family<StopInfo?, String>((ref, stopId) {
  final repoAsync = ref.watch(gtfsRepositoryProvider);
  final repo = repoAsync.asData?.value;
  return repo?.stopsById[stopId];
});

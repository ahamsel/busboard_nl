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
import '../domain/map/bus_motion_engine.dart';
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
      refreshIntervalSeconds: prefs.getInt('refreshInterval') ?? 5,
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

// ─── Bus Motion Engine ────────────────────────────────────

final busMotionEngineProvider = Provider<BusMotionEngine?>((ref) {
  final repoAsync = ref.watch(gtfsRepositoryProvider);
  final repo = repoAsync.asData?.value;
  if (repo == null) return null;
  return BusMotionEngine(repo);
});

final busTrackingStreamProvider = StreamProvider<Map<String, BusTrackingState>>((
  ref,
) async* {
  final engine = ref.watch(busMotionEngineProvider);
  if (engine == null) {
    yield {};
    return;
  }

  final api = ref.read(timetrackApiProvider);
  final refreshIntervalSeconds = ref.watch(
    settingsProvider.select((s) => s.refreshIntervalSeconds),
  );
  final interval = Duration(seconds: refreshIntervalSeconds);
  final speedFidelityTracker = _SpeedFidelityTracker();

  // Initial fetch
  final initialNow = DateTime.now();
  final initialResult = await api.fetchVehiclesResult();
  final vehicles = initialResult.vehicles;
  if (initialResult.succeeded) {
    engine.processBatch(vehicles, initialNow);
  } else if (kDebugMode) {
    debugPrint('[Map] Live-data initial fetch failed: ${initialResult.error}');
  }
  if (kDebugMode) {
    final snapped = engine.states.values
        .where((s) => s.shapeId != null && s.progressAlongRoute != null)
        .length;
    final d = engine.diagnostics;
    final speedFidelity = speedFidelityTracker.summarize(
      engine: engine,
      now: initialNow,
    );
    final correction = d.correctionP50Meters == null
        ? 'n/a'
        : 'p50=${d.correctionP50Meters!.toStringAsFixed(1)}m '
              'p90=${(d.correctionP90Meters ?? 0).toStringAsFixed(1)}m '
              'mean=${(d.correctionMeanMeters ?? 0).toStringAsFixed(1)}m';
    final innovation = d.innovationP50Meters == null
        ? 'n/a'
        : 'p50=${d.innovationP50Meters!.toStringAsFixed(1)}m '
              'p90=${(d.innovationP90Meters ?? 0).toStringAsFixed(1)}m '
              'mean=${(d.innovationMeanMeters ?? 0).toStringAsFixed(1)}m';
    final tuning =
        'auto=${d.autoAdjustEnabled ? "on" : "off"} '
        'accel=${d.kalmanAccelStdMps2.toStringAsFixed(2)} '
        'meas=${d.kalmanMeasurementStdM.toStringAsFixed(1)} '
        'blend=${d.blendDurationMs}ms';
    debugPrint(
      '[Map] Live-data initial fetch: '
      'source=${initialResult.source?.label ?? "unknown"}, '
      'vehicles=${vehicles.length}, '
      'states=${engine.states.length}, snapped=$snapped, '
      'assignDup=${d.duplicateVehicleAssignments}, '
      'accepted=${d.acceptedUpdates}, '
      'obsDup=${d.duplicateOrOutOfOrderUpdates}, '
      'rejected=${d.rejectedOutliers}, correction=$correction, '
      'innovation=$innovation, speedFidelity=$speedFidelity, tuning=$tuning',
    );
  }
  yield Map.unmodifiable(engine.states);

  // Poll at refresh interval
  await for (final _ in Stream.periodic(interval)) {
    try {
      final pollNow = DateTime.now();
      final result = await api.fetchVehiclesResult();
      if (!result.succeeded) {
        if (kDebugMode) {
          debugPrint('[Map] Live-data poll failed: ${result.error}');
        }
        continue;
      }
      final vehicles = result.vehicles;
      engine.processBatch(vehicles, pollNow);
      if (kDebugMode) {
        final snapped = engine.states.values
            .where((s) => s.shapeId != null && s.progressAlongRoute != null)
            .length;
        final d = engine.diagnostics;
        final speedFidelity = speedFidelityTracker.summarize(
          engine: engine,
          now: pollNow,
        );
        final correction = d.correctionP50Meters == null
            ? 'n/a'
            : 'p50=${d.correctionP50Meters!.toStringAsFixed(1)}m '
                  'p90=${(d.correctionP90Meters ?? 0).toStringAsFixed(1)}m '
                  'mean=${(d.correctionMeanMeters ?? 0).toStringAsFixed(1)}m';
        final innovation = d.innovationP50Meters == null
            ? 'n/a'
            : 'p50=${d.innovationP50Meters!.toStringAsFixed(1)}m '
                  'p90=${(d.innovationP90Meters ?? 0).toStringAsFixed(1)}m '
                  'mean=${(d.innovationMeanMeters ?? 0).toStringAsFixed(1)}m';
        final tuning =
            'auto=${d.autoAdjustEnabled ? "on" : "off"} '
            'accel=${d.kalmanAccelStdMps2.toStringAsFixed(2)} '
            'meas=${d.kalmanMeasurementStdM.toStringAsFixed(1)} '
            'blend=${d.blendDurationMs}ms';
        debugPrint(
          '[Map] Live-data poll: source=${result.source?.label ?? "unknown"}, '
          'vehicles=${vehicles.length}, '
          'states=${engine.states.length}, snapped=$snapped, '
          'assignDup=${d.duplicateVehicleAssignments}, '
          'accepted=${d.acceptedUpdates}, '
          'obsDup=${d.duplicateOrOutOfOrderUpdates}, '
          'rejected=${d.rejectedOutliers}, correction=$correction, '
          'innovation=$innovation, speedFidelity=$speedFidelity, tuning=$tuning',
        );
      }
      yield Map.unmodifiable(engine.states);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Map] Live-data poll error: $e');
      }
      // Continue on error
    }
  }
});

// ─── Stop Info helper ──────────────────────────────────────

final stopInfoProvider = Provider.family<StopInfo?, String>((ref, stopId) {
  final repoAsync = ref.watch(gtfsRepositoryProvider);
  final repo = repoAsync.asData?.value;
  return repo?.stopsById[stopId];
});

class _SpeedFidelityTracker {
  final Map<String, _SpeedFidelitySample> _previousByKey = {};

  String summarize({required BusMotionEngine engine, required DateTime now}) {
    final rendered = engine.interpolate(now);
    final renderedProgress = engine.debugRenderedProgressByKey;
    final liveKeys = <String>{};
    final ratios = <double>[];

    for (final key in rendered.keys) {
      liveKeys.add(key);
      final progress = renderedProgress[key];
      final state = engine.states[key];
      if (progress == null || state == null) continue;

      final lastGood = state.observations.lastWhere(
        (o) => !o.rejected,
        orElse: () => state.observations.last,
      );
      final apiSpeedKmh = lastGood.speed.abs();
      final previous = _previousByKey[key];
      if (previous != null) {
        final dt = now.difference(previous.time).inMilliseconds / 1000.0;
        if (dt > 0.0 && apiSpeedKmh >= 2.0) {
          final displayedKmh =
              ((progress - previous.progressM).abs() / dt) * 3.6;
          final ratio = displayedKmh / apiSpeedKmh;
          if (ratio.isFinite && ratio >= 0.0) {
            ratios.add(ratio.clamp(0.0, 8.0));
          }
        }
      }

      _previousByKey[key] = _SpeedFidelitySample(
        time: now,
        progressM: progress,
      );
    }

    _previousByKey.removeWhere((key, _) => !liveKeys.contains(key));
    if (ratios.isEmpty) return 'n/a';

    final p50 = _percentile(ratios, 0.50);
    final p90 = _percentile(ratios, 0.90);
    final mean = ratios.reduce((a, b) => a + b) / ratios.length;
    return 'p50=${p50.toStringAsFixed(2)} '
        'p90=${p90.toStringAsFixed(2)} '
        'mean=${mean.toStringAsFixed(2)} '
        'n=${ratios.length}';
  }
}

class _SpeedFidelitySample {
  final DateTime time;
  final double progressM;

  const _SpeedFidelitySample({required this.time, required this.progressM});
}

double _percentile(List<double> values, double q) {
  if (values.isEmpty) return 0.0;
  final sorted = List<double>.from(values)..sort();
  final idx = ((sorted.length - 1) * q).round().clamp(0, sorted.length - 1);
  return sorted[idx];
}

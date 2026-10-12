import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime/service_alert_models.dart';
import '../domain/trip_planner/journey.dart';
import 'providers.dart';
import 'trip_planner_providers.dart';

/// Active alerts that touch the rider: their stop, the routes serving it, or the routes of their saved
/// trips' next buses (spec 2026-10-12 §3.1).
final alertsForYouProvider = Provider.autoDispose<List<ServiceAlert>>((ref) {
  final updates = ref.watch(serviceUpdatesProvider).value;
  final repo = ref.watch(gtfsRepositoryProvider).value;
  if (updates == null || repo == null) return const [];
  final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
  final routes = <String>{if (stopId != null) ...repo.routeShortNamesForStop(stopId)};
  for (final trip in ref.watch(savedTripsProvider).value ?? const []) {
    for (final j in ref.watch(savedTripNextProvider(trip.id)).value ?? const <Journey>[]) {
      for (final ride in j.legs.whereType<RideLeg>()) {
        final name = repo.routesById[ride.routeId]?.routeShortName;
        if (name != null) routes.add(name);
      }
    }
  }
  if (stopId == null && routes.isEmpty) return const [];
  return updates
      .activeAlertsAt(DateTime.now())
      .where((a) => a.appliesTo(routeIds: routes, stopId: stopId))
      .toList();
});

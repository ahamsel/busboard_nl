import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/realtime/service_alert_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../alerts/service_alert_card.dart';
import '../arrival_alerts/alert_bell.dart';
import '../arrival_alerts/alert_strip.dart';
import '../board/arrival_row_tile.dart';
import '../kit/kit.dart';

/// A stop's sheet: everything the Board showed (spec 2026-10-12 §3.2).
abstract final class StopSheetContent {
  static const starKey = ValueKey('stop-star');
  static const refreshKey = ValueKey('stop-refresh');
  static const planFromKey = ValueKey('stop-plan-from');
  static Widget header(String stopId) => _StopHeader(stopId: stopId);
  static Widget body(String stopId) => _StopBody(stopId: stopId);
}

class _StopHeader extends ConsumerWidget {
  const _StopHeader({required this.stopId});
  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stop = ref.watch(stopInfoProvider(stopId));
    final name = stop?.stopName ?? 'Stop $stopId';
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    final checking = rows == null && !arrivals.hasError;
    final live = rows != null && rows.any((r) => r.isLive);
    final mine = ref.watch(settingsProvider.select((s) => s.selectedStopId)) == stopId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.s, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            BBPill(label: 'STOP $stopId', background: bb.colors.ink, foreground: bb.colors.bg),
            const Spacer(),
            BBIconButton(
              key: StopSheetContent.starKey,
              icon: mine ? BBIcons.star : BBIcons.starOutline,
              semanticLabel: mine ? 'Your stop' : 'Set as my stop',
              onPressed: mine ? null : () => ref.read(settingsProvider.notifier).setSelectedStop(stopId),
            ),
            // The sheet owns the drag, so there is no pull to refresh: this button does it.
            BBIconButton(
              key: StopSheetContent.refreshKey,
              icon: BBIcons.refresh,
              semanticLabel: 'Refresh departures',
              onPressed: () => ref.invalidate(stopArrivalsProvider(stopId)),
            ),
          ]),
          Semantics(
            header: true,
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: bb.text.headline),
          ),
          const SizedBox(height: BBSpace.xs),
          Row(children: [
            BBGlyph(BBGlyphKind.liveDot, size: 12, color: live ? bb.colors.live : bb.colors.muted),
            const SizedBox(width: BBSpace.s),
            Flexible(
              child: Semantics(
                // Silent while the first load is in flight so assistive tech never hears a provisional negative state.
                liveRegion: !checking,
                child: Text(
                  checking
                      ? 'Checking live data…'
                      : live
                          ? 'Live'
                          : 'Showing schedule',
                  style: bb.text.caption,
                ),
              ),
            ),
          ]),
          const SizedBox(height: BBSpace.s),
          BBButton(
            key: StopSheetContent.planFromKey,
            label: 'Plan a trip from here',
            icon: BBIcons.plan,
            kind: BBButtonKind.quiet,
            expand: true,
            wrap: true,
            onPressed: () {
              ref.read(planQueryProvider.notifier).setFrom(StopPlace(stopId: stopId, name: name));
              context.push('/search');
            },
          ),
        ],
      ),
    );
  }
}

class _StopBody extends ConsumerWidget {
  const _StopBody({required this.stopId});
  final String stopId;

  List<ServiceAlert> _relevant(ServiceUpdates? updates, List<ArrivalRow> rows) {
    if (updates == null) return const [];
    final routes = rows.map((a) => a.routeShortName).toSet();
    final trips = rows.map((a) => a.tripId).toSet();
    return updates
        .activeAlertsAt(DateTime.now())
        .where((a) => a.appliesTo(routeIds: routes, stopId: stopId, tripIds: trips))
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every new list feeds the arrival alerts, as the Board did.
    ref.listen<AsyncValue<List<ArrivalRow>>>(stopArrivalsProvider(stopId), (_, next) {
      final rows = next.value;
      if (rows != null) ref.read(arrivalAlertProvider.notifier).onBoardArrivals(stopId, rows);
    });
    final stop = ref.watch(stopInfoProvider(stopId));
    final name = stop?.stopName ?? 'Stop $stopId';
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    final alerts = _relevant(ref.watch(serviceUpdatesProvider).value, rows ?? const []);
    final hasStrip = ref.watch(arrivalAlertProvider).value != null;

    VoidCallback? follow(ArrivalRow a) {
      final vehicle = a.followableVehicle;
      if (vehicle == null) return null;
      return () {
        ref.read(homeSheetProvider.notifier).home();
        ref.read(followProvider.notifier).follow(vehicle);
      };
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasStrip) ...[const AlertStrip(), const SizedBox(height: BBSpace.s)],
          if (alerts.isNotEmpty) ...[
            ServiceAlertCard(
              alert: alerts.first,
              stopNames: stop == null ? const {} : {stopId: stop.stopName},
              compact: true,
              onTap: () => context.push('/alerts'),
            ),
            if (alerts.length > 1)
              BBButton(
                label: '${alerts.length - 1} more relevant ${alerts.length == 2 ? "alert" : "alerts"}',
                kind: BBButtonKind.quiet,
                onPressed: () => context.push('/alerts'),
              ),
            const SizedBox(height: BBSpace.s),
          ],
          if (rows == null && arrivals.hasError)
            const BBEmptyState(icon: BBIcons.error, tone: BBEmptyTone.error, title: "Couldn't load departures")
          else if (rows == null)
            const BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 5, label: 'Loading departures...')
          else if (rows.isEmpty)
            const BBEmptyState(
              icon: BBIcons.schedule,
              title: 'No upcoming departures',
              message: 'There are no scheduled departures\nfrom this stop right now.',
            )
          else
            for (final a in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: BBSpace.s),
                child: ArrivalRowTile(
                  arrival: a,
                  onTap: follow(a),
                  action: AlertBell(arrival: a, stopId: stopId, stopName: name),
                ),
              ),
        ],
      ),
    );
  }
}

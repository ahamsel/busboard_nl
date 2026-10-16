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
import 'follow_tip.dart';

/// A stop's sheet: everything the Board showed (spec 2026-10-12 §3.2).
abstract final class StopSheetContent {
  static const starKey = ValueKey('stop-star');
  static const refreshKey = ValueKey('stop-refresh');
  static const planFromKey = ValueKey('stop-plan-from');
  static const closeKey = ValueKey('stop-close');
  static const openBoardKey = ValueKey('stop-open-board');
  static const showMapKey = ValueKey('stop-show-map');
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
    final updatedAt = ref.watch(stopArrivalsUpdatedAtProvider.select((m) => m[stopId]));
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
            // Back to what was under the sheet: the way out for a screen reader, the side panel (no drag) and
            // iPhone (no system back), as well as a swipe down (spec §3.2).
            BBIconButton(
              key: StopSheetContent.closeKey,
              icon: BBIcons.close,
              semanticLabel: 'Close',
              onPressed: () => ref.read(homeSheetProvider.notifier).back(),
            ),
          ]),
          Semantics(
            header: true,
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: bb.text.headline),
          ),
          const SizedBox(height: BBSpace.xs),
          Row(children: [
            BBLiveDot(color: live ? bb.colors.live : bb.colors.muted, breathing: live),
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
            // Outside the live region, so assistive tech hears live <-> schedule changes, not every refresh time.
            // Flexible too, so at large text the pair shares the row and wraps instead of crushing the state label.
            if (live && updatedAt != null)
              Flexible(
                child: Text(
                  ' · updated ${BBTime.of(updatedAt, use24h: BBTime.use24h(context), seconds: true)}',
                  style: bb.text.caption,
                ),
              ),
          ]),
          const SizedBox(height: BBSpace.s),
          // For riders used to the Board tab: the whole Board in one tap (the sheet at full height; on the tablet panel,
          // its departures). With the Board open it turns into the way back: "Show map" brings the sheet to half over
          // the stop. One button either way, so the header keeps one height and the detents never move under a drag.
          Padding(
            // The header is padded l on the left but s on the right (for the icon buttons' own hit area): this evens
            // the filled button's sides.
            padding: const EdgeInsets.only(right: BBSpace.l - BBSpace.s),
            child: ref.watch(sheetAtFullProvider) == sheetIdOf(StopSheet(stopId))
                ? BBButton(
                    key: StopSheetContent.showMapKey,
                    label: 'Show map',
                    semanticLabel: 'Show the map, $name',
                    icon: BBIcons.map,
                    expand: true,
                    wrap: true,
                    onPressed: () => ref.read(homeSheetProvider.notifier).showMap(),
                  )
                : BBButton(
                    key: StopSheetContent.openBoardKey,
                    label: 'Open board',
                    semanticLabel: 'Open board, $name',
                    icon: BBIcons.board,
                    expand: true,
                    wrap: true,
                    onPressed: () => ref.read(homeSheetProvider.notifier).openBoard(stopId),
                  ),
          ),
          BBButton(
            key: StopSheetContent.planFromKey,
            label: 'Plan a trip from here',
            icon: BBIcons.plan,
            kind: BBButtonKind.quiet,
            expand: true,
            wrap: true,
            onPressed: () {
              // A new trip from this stop, leaving now; the search's pick keeps this start (Ruling 14).
              ref.read(planQueryProvider.notifier).startFrom(StopPlace(stopId: stopId, name: name));
              context.push('/search?keep=1');
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

    // A row with no bus to follow says why, and stays where it is (spec 2026-10-14 §4.2).
    void explain(ArrivalRow a) => BBToast.show(context, ArrivalRowTile.whyNotFollowable(a), announce: true);

    // Rows are keyed by trip and scheduled time (a loop route can pass a stop twice on one trip), plus a count for
    // exact repeats, so no two rows ever share a key.
    final seen = <(String, int), int>{};
    final rowKeys = [
      for (final a in rows ?? const <ArrivalRow>[])
        (
          a.tripId,
          a.scheduledTime.totalSeconds,
          seen.update((a.tripId, a.scheduledTime.totalSeconds), (n) => n + 1, ifAbsent: () => 0),
        ),
    ];

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
            // Rows enter staggered on first show, and slide when the list reorders (spec §3.2). Built only once the
            // data is here, so the stagger plays after the skeleton rather than behind it.
            BBListMotion(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, a) in rows.indexed)
                    BBListItem(
                      key: ValueKey(rowKeys[i]),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: BBSpace.s),
                        child: ArrivalRowTile(
                          arrival: a,
                          onTap: follow(a),
                          onExplain: () => explain(a),
                          action: AlertBell(arrival: a, stopId: stopId, stopName: name),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // While a departure is live: the one-time "tap to follow" tip (spec 2026-10-14 §4.3).
          if (rows != null && rows.any((r) => r.followableVehicle != null)) const FollowTip(),
        ],
      ),
    );
  }
}

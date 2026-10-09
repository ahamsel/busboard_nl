import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../alerts/service_alert_card.dart';
import '../board/arrival_row_tile.dart';
import '../kit/kit.dart';

/// Stop card header (spec §3.3): stop pole, name, stop number.
class StopCardHeader extends StatelessWidget {
  const StopCardHeader({super.key, required this.stop});

  final StopInfo stop;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.m),
      child: Row(
        children: [
          BBGlyph(BBGlyphKind.stopPole, size: 28, color: bb.colors.brand),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stop.stopName, style: bb.text.headline, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('Stop ${stop.stopId}', style: bb.text.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stop card body: next arrivals, any stop alert, Open board, Plan a trip from here, Set as my stop.
class StopCardBody extends ConsumerWidget {
  const StopCardBody({super.key, required this.stop});

  final StopInfo stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMine = ref.watch(settingsProvider.select((s) => s.selectedStopId)) == stop.stopId;
    final alerts = ref
            .watch(serviceUpdatesProvider)
            .value
            ?.activeAlertsAt(DateTime.now())
            .where((a) => a.appliesTo(routeIds: const {}, stopId: stop.stopId))
            .toList() ??
        const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArrivalsPreview(stopId: stop.stopId, max: 3),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: BBSpace.m),
            ServiceAlertCard(
              alert: alerts.first,
              stopNames: {stop.stopId: stop.stopName},
              compact: true,
              onTap: () => context.go('/alerts'),
            ),
          ],
          const SizedBox(height: BBSpace.l),
          BBButton(
            label: 'Open board',
            icon: BBIcons.board,
            expand: true,
            onPressed: () => context.go('/board/${stop.stopId}'),
          ),
          const SizedBox(height: BBSpace.s),
          BBButton(
            label: 'Plan a trip from here',
            icon: BBIcons.plan,
            kind: BBButtonKind.quiet,
            expand: true,
            wrap: true,
            onPressed: () {
              ref.read(planQueryProvider.notifier).setFrom(StopPlace(stopId: stop.stopId, name: stop.stopName));
              context.go('/plan');
            },
          ),
          const SizedBox(height: BBSpace.s),
          BBButton(
            label: isMine ? 'Your stop' : 'Set as my stop',
            icon: isMine ? BBIcons.star : BBIcons.starOutline,
            kind: BBButtonKind.quiet,
            expand: true,
            onPressed: isMine ? null : () => ref.read(settingsProvider.notifier).setSelectedStop(stop.stopId),
          ),
        ],
      ),
    );
  }
}

/// The next [max] arrivals at a stop, or a skeleton while the first load runs.
class ArrivalsPreview extends ConsumerWidget {
  const ArrivalsPreview({super.key, required this.stopId, this.max});

  final String stopId;
  final int? max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    if (rows == null) {
      return arrivals.hasError
          ? Text("Couldn't load arrivals", style: bb.text.caption)
          : BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: max ?? 3);
    }
    if (rows.isEmpty) return Text('No buses due soon', style: bb.text.caption);
    return ArrivalsList(rows: max == null ? rows : rows.take(max!).toList());
  }
}

/// A column of arrival rows.
class ArrivalsList extends StatelessWidget {
  const ArrivalsList({super.key, required this.rows});

  final List<ArrivalRow> rows;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final a in rows) ArrivalRowTile(arrival: a)],
      );
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/gtfs/gtfs_repository.dart';
import '../../domain/trip_planner/journey.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';

/// Whole minutes, rounded, for a span of seconds.
int planMinutes(int seconds) => (seconds / 60).round();

/// The badge text for a ride: the route's short name, as the Board shows it.
String routeNameOf(String routeId, GtfsRepository? repo) => repo?.routesById[routeId]?.routeShortName ?? routeId;

String _minutes(int m) => m == 1 ? '1 minute' : '$m minutes';

/// One sentence for screen readers, e.g. "Leave 8:12 AM, arrive 8:47 AM, 35 minutes, route 10 then route 2,
/// 5 minutes walking, live times".
String journeySummary(Journey j, GtfsRepository? repo, {bool use24h = false}) {
  final routes = j.legs.whereType<RideLeg>().map((r) => 'route ${routeNameOf(r.routeId, repo)}').join(' then ');
  final walk = planMinutes(j.walkSeconds);
  return [
    'Leave ${BBTime.of(j.at(j.departs), use24h: use24h)}',
    'arrive ${BBTime.of(j.at(j.arrives), use24h: use24h)}',
    _minutes(planMinutes(j.arrives - j.departs)),
    if (routes.isNotEmpty) routes,
    if (walk >= 1) '${_minutes(walk)} walking',
    if (j.usesLive) 'live times',
    if (j.replannedForLiveTimes) 'changed for live times',
  ].join(', ');
}

/// One planned trip in the results: times, total minutes, the routes in order, the walking and live markers.
class JourneyCard extends ConsumerWidget {
  const JourneyCard({super.key, required this.journey, required this.onTap});

  final Journey journey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final j = journey;
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final use24h = BBTime.use24h(context);
    String clock(int s) => BBTime.of(j.at(s), use24h: use24h);
    final rides = j.legs.whereType<RideLeg>().toList();
    final walk = planMinutes(j.walkSeconds);

    return BBCard(
      onTap: onTap,
      semanticLabel: journeySummary(j, repo, use24h: use24h),
      padding: const EdgeInsets.all(BBSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('${clock(j.departs)} → ${clock(j.arrives)}', style: bb.text.headline)),
              const SizedBox(width: BBSpace.s),
              Text('${planMinutes(j.arrives - j.departs)} min', style: bb.text.label.copyWith(color: bb.colors.ink)),
            ],
          ),
          const SizedBox(height: BBSpace.s),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < rides.length; i++) ...[
                if (i > 0) Text('›', style: bb.text.label.copyWith(color: bb.colors.muted)),
                RouteBadge.name(routeNameOf(rides[i].routeId, repo), size: RouteBadgeSize.compact),
              ],
              if (walk >= 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(BBIcons.walk, size: 16, color: bb.colors.muted),
                    const SizedBox(width: 2),
                    Text('$walk min walk', style: bb.text.caption),
                  ],
                ),
              if (j.usesLive) const BBPill(label: 'Live', tone: BBPillTone.live, leadingDot: true),
            ],
          ),
          if (j.replannedForLiveTimes) ...[
            const SizedBox(height: BBSpace.s),
            Row(
              children: [
                Icon(BBIcons.warning, size: 16, color: bb.colors.warnInk),
                const SizedBox(width: BBSpace.xs),
                Flexible(
                  child: Text('Changed for live times', style: bb.text.caption.copyWith(color: bb.colors.warnInk)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

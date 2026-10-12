import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/location/nearest_stop_service.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';

class NearMeList extends ConsumerWidget {
  const NearMeList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final nearbyAsync = ref.watch(nearestStopsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(BBIcons.nearMe, size: 20, color: bb.colors.liveInk),
          const SizedBox(width: BBSpace.s),
          Expanded(child: Semantics(header: true, child: Text('Near me', style: bb.text.headline))),
          nearbyAsync.when(
            loading: () => const SizedBox(width: 44, height: 44),
            error: (_, _) => const SizedBox.shrink(),
            data: (_) => BBIconButton(
              icon: BBIcons.refresh,
              semanticLabel: 'Refresh location',
              onPressed: () => ref.invalidate(nearestStopsProvider),
            ),
          ),
        ]),
        nearbyAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: BBSpace.s),
            child: BBSkeleton(kind: BBSkeletonKind.stopCard, count: 3, label: 'Finding nearby stops...'),
          ),
          error: (_, _) => BBEmptyState(
            icon: BBIcons.locationOff,
            tone: BBEmptyTone.error,
            title: 'Unable to get location',
            message: 'Please enable location services and grant permission.',
            action: BBButton(
              label: 'Try again',
              icon: BBIcons.refresh,
              kind: BBButtonKind.quiet,
              onPressed: () => ref.invalidate(nearestStopsProvider),
            ),
          ),
          data: (stops) {
            if (stops.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(BBSpace.xxl),
                child: Text(
                  'No stops found within 800m.',
                  textAlign: TextAlign.center,
                  style: bb.text.body.copyWith(color: bb.colors.muted),
                ),
              );
            }
            return Column(children: [
              for (var i = 0; i < stops.length; i++) ...[
                if (i > 0) const BBDivider(indent: 52),
                _NearbyStopTile(nearby: stops[i]),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _NearbyStopTile extends ConsumerWidget {
  const _NearbyStopTile({required this.nearby});

  final NearbyStop nearby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stop = nearby.stop;
    final routes =
        ref.watch(gtfsRepositoryProvider).asData?.value.routeDirectionsForStop(stop.stopId) ?? const <RouteDirections>[];
    final routesText = routes.isEmpty ? '' : ', routes ${routes.map(_spokenDirections).join(', ')}';
    return BBPressable(
      semanticLabel: '${stop.stopName}, stop ${stop.stopId}, ${nearby.distanceDisplay} away$routesText',
      onTap: () {
        ref.read(settingsProvider.notifier).setSelectedStop(stop.stopId);
        context.push('/board/${stop.stopId}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BBSpace.m),
        child: Row(children: [
          const BBIconTile(icon: BBIcons.bus),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stop.stopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.headline),
              Text('Stop ${stop.stopId} · ${nearby.distanceDisplay}', style: bb.text.caption),
              if (routes.isNotEmpty) ...[
                const SizedBox(height: BBSpace.xs),
                Wrap(spacing: BBSpace.m, runSpacing: BBSpace.xs, children: [
                  for (final r in routes) _RouteDirectionsChip(directions: r),
                ]),
              ],
            ]),
          ),
          Icon(BBIcons.chevronRight, color: bb.colors.muted),
        ]),
      ),
    );
  }
}

/// "10 to Downtown or Kelsey Drive"; just "24" when no trip leaves from here.
String _spokenDirections(RouteDirections r) =>
    r.destinations.isEmpty ? r.routeShortName : '${r.routeShortName} to ${r.destinations.join(' or ')}';

/// A route chip followed by where the route goes from this stop.
class _RouteDirectionsChip extends StatelessWidget {
  const _RouteDirectionsChip({required this.directions});

  final RouteDirections directions;

  @override
  Widget build(BuildContext context) {
    final badge = RouteBadge.name(directions.routeShortName, size: RouteBadgeSize.compact);
    if (directions.destinations.isEmpty) return badge;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      badge,
      const SizedBox(width: BBSpace.xs),
      Flexible(
        child: Text(
          directions.destinations.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.bb.text.caption,
        ),
      ),
    ]);
  }
}

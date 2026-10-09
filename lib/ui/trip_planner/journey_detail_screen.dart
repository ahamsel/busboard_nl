import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/gtfs/gtfs_repository.dart';
import '../../data/realtime/timetrack_api.dart';
import '../../data/trip_planner/saved_trip_store.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/arrival_service.dart';
import '../../domain/trip_planner/journey.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/follow_providers.dart';
import '../../state/journey_on_map_provider.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../arrival_alerts/alert_bell.dart';
import '../kit/kit.dart';
import 'journey_card.dart';

/// The arrival the Board shows for [leg]'s trip at its board stop: the Board's own row (same service, same live
/// vehicles), the call nearest the leg's departure. Null when the journey isn't today or the Board wouldn't list
/// that bus (more than 3 hours away, or gone).
ArrivalRow? boardArrivalFor(Journey j, RideLeg leg, GtfsRepository repo, TimeTrackFetchResult? feed, DateTime now) {
  final day = j.serviceDate;
  if (day.year != now.year || day.month != now.month || day.day != now.day) return null;
  final rows = ArrivalService(repo).getUpcomingArrivals(
    stopId: leg.boardStopId,
    now: now,
    maxResults: 1 << 20,
    liveVehicles: feed != null && feed.succeeded ? feed.vehicles : null,
  );
  ArrivalRow? best;
  int? bestGap;
  for (final r in rows) {
    if (r.tripId != leg.tripId) continue;
    final gap = (r.scheduledTime.totalSeconds - leg.departs).abs();
    if (bestGap == null || gap < bestGap) {
      best = r;
      bestGap = gap;
    }
  }
  return best;
}

/// One planned trip, leg by leg (spec §2.3): the timeline, Follow and the bell on the first ride, Show on map and
/// Save trip.
class JourneyDetailScreen extends ConsumerStatefulWidget {
  const JourneyDetailScreen({super.key, required this.journey});

  final Journey journey;

  @override
  ConsumerState<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends ConsumerState<JourneyDetailScreen> {
  /// An add is in flight: a second tap must not fire another.
  bool _saving = false;

  Future<void> _save(Place from, Place to) async {
    setState(() => _saving = true);
    try {
      final trips = await ref.read(savedTripsProvider.future);
      if (!mounted) return;
      final same = trips.any((t) => t.from == from && t.to == to);
      if (trips.length >= maxSavedTrips && !same) {
        BBToast.show(context, 'You can save up to $maxSavedTrips trips');
        return;
      }
      final added = await ref.read(savedTripsProvider.notifier).add(SavedTrip(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: '${from.label} → ${to.label}',
            from: from,
            to: to,
          ));
      if (mounted) BBToast.show(context, added ? 'Saved' : 'Already saved');
    } catch (_) {
      if (mounted) BBToast.show(context, "Couldn't save the trip");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final j = widget.journey;
    final repo = ref.watch(gtfsRepositoryProvider).value;
    // Watched for the live bus on the first ride; it refreshes every 30 s, and the bell and Follow with it.
    final feed = ref.watch(plannerLiveFeedProvider).value;
    final draft = ref.watch(planQueryProvider);
    final saved = ref.watch(savedTripsProvider).value ?? const <SavedTrip>[];
    final now = ref.read(plannerClockProvider)();
    final use24h = BBTime.use24h(context);
    String clock(int s) => BBTime.of(j.at(s), use24h: use24h);

    final from = draft.from;
    final to = draft.to;
    final isSaved = from != null && to != null && saved.any((t) => t.from == from && t.to == to);
    final firstRide = j.legs.whereType<RideLeg>().firstOrNull;
    final arrival = firstRide == null || repo == null ? null : boardArrivalFor(j, firstRide, repo, feed, now);
    final onSave = from == null || to == null || _saving ? null : () => _save(from, to);

    return BBScaffold(
      body: ListView(
        children: [
          BBTopBar(
            title: 'Your trip',
            subtitle: 'Leave ${clock(j.departs)} · arrive ${clock(j.arrives)}',
            onBack: () => context.pop(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BBSpace.screen),
            child: BBCard(
              padding: const EdgeInsets.all(BBSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final leg in j.legs)
                    if (leg is RideLeg) ...[
                      _RideRow(leg: leg, repo: repo, clock: clock),
                      if (identical(leg, firstRide) && arrival != null)
                        _FirstRideActions(arrival: arrival, stopId: leg.boardStopId, stopName: _stopName(repo, leg.boardStopId)),
                      const SizedBox(height: BBSpace.l),
                    ] else if (leg is WalkLeg && leg.seconds > 0) ...[
                      _WalkRow(leg: leg, repo: repo, clock: clock),
                      const SizedBox(height: BBSpace.l),
                    ],
                  _TimelineRow(
                    leading: Icon(BBIcons.stop, size: 22, color: bb.colors.brand),
                    children: [Text('Arrive ${clock(j.arrives)}', style: bb.text.headline)],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.l, BBSpace.screen, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BBButton(
                  label: 'Show on map',
                  icon: BBIcons.map,
                  expand: true,
                  wrap: true,
                  onPressed: () {
                    ref.read(journeyOnMapProvider.notifier).show(j);
                    context.go('/map');
                  },
                ),
                const SizedBox(height: BBSpace.s),
                Semantics(
                  button: true,
                  enabled: onSave != null,
                  label: isSaved ? 'Save trip, saved' : 'Save trip',
                  onTap: onSave,
                  excludeSemantics: true,
                  child: BBButton(
                    label: 'Save trip',
                    icon: isSaved ? BBIcons.star : BBIcons.starOutline,
                    kind: BBButtonKind.quiet,
                    expand: true,
                    wrap: true,
                    onPressed: onSave,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: BBNavBar.reservedHeight(context) + BBSpace.l),
        ],
      ),
    );
  }
}

String _stopName(GtfsRepository? repo, String stopId) => repo?.stopsById[stopId]?.stopName ?? 'Stop $stopId';

/// "MUN Centre (1150)".
String _stopLabel(GtfsRepository? repo, String stopId) => '${_stopName(repo, stopId)} ($stopId)';

/// A timeline row: a fixed-width mark (icon or badge), then its lines, read as one.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.leading, required this.children});

  final Widget leading;
  final List<Widget> children;

  static const markWidth = 40.0;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: markWidth),
              child: Center(widthFactor: 1, child: leading),
            ),
            const SizedBox(width: BBSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ],
        ),
      );
}

class _WalkRow extends StatelessWidget {
  const _WalkRow({required this.leg, required this.repo, required this.clock});

  final WalkLeg leg;
  final GtfsRepository? repo;
  final String Function(int seconds) clock;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final minutes = planMinutes(leg.seconds).clamp(1, 1 << 20);
    final to = leg.toStopId;
    return _TimelineRow(
      leading: Icon(BBIcons.walk, size: 22, color: bb.colors.muted),
      children: [
        Text('Walk $minutes min to ${to == null ? 'your destination' : _stopLabel(repo, to)}', style: bb.text.body),
        Text(clock(leg.startSeconds), style: bb.text.caption),
      ],
    );
  }
}

class _RideRow extends StatelessWidget {
  const _RideRow({required this.leg, required this.repo, required this.clock});

  final RideLeg leg;
  final GtfsRepository? repo;
  final String Function(int seconds) clock;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final stops = leg.stopCount == 1 ? '1 stop' : '${leg.stopCount} stops';
    return _TimelineRow(
      leading: RouteBadge.name(routeNameOf(leg.routeId, repo)),
      children: [
        Text('${clock(leg.departs)} → ${clock(leg.arrives)} · $stops', style: bb.text.headline),
        const SizedBox(height: 2),
        Text('Get on at ${_stopLabel(repo, leg.boardStopId)}', style: bb.text.body),
        Text('Get off at ${_stopLabel(repo, leg.alightStopId)}', style: bb.text.body),
        if (leg.live) ...[
          const SizedBox(height: BBSpace.xs),
          const BBPill(label: 'Live', tone: BBPillTone.live, leadingDot: true),
        ],
      ],
    );
  }
}

/// Follow and the bell for the first ride, by the Board's rules: Follow for a live row with a known bus, the bell
/// when [AlertBell] allows it.
class _FirstRideActions extends ConsumerWidget {
  const _FirstRideActions({required this.arrival, required this.stopId, required this.stopName});

  final ArrivalRow arrival;
  final String stopId;
  final String stopName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = arrival.vehicleNumber;
    final followable = arrival.isLive && vehicle != null && vehicle.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(left: _TimelineRow.markWidth + BBSpace.m, top: BBSpace.s),
      child: Wrap(
        spacing: BBSpace.s,
        runSpacing: BBSpace.s,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (followable)
            Semantics(
              button: true,
              label: 'Follow bus $vehicle on the map',
              onTap: () => _follow(context, ref, vehicle),
              excludeSemantics: true,
              child: BBButton(
                label: 'Follow bus',
                icon: BBIcons.bus,
                kind: BBButtonKind.quiet,
                wrap: true,
                onPressed: () => _follow(context, ref, vehicle),
              ),
            ),
          AlertBell(arrival: arrival, stopId: stopId, stopName: stopName),
        ],
      ),
    );
  }

  void _follow(BuildContext context, WidgetRef ref, String vehicle) {
    ref.read(followProvider.notifier).follow(vehicle);
    context.go('/map');
  }
}

import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/gtfs/gtfs_repository.dart';
import '../../data/realtime/timetrack_api.dart';
import '../../data/trip_planner/saved_trip_store.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/arrival_service.dart';
import '../../domain/arrival_alerts/alert_tracker.dart';
import '../../domain/location/nearest_stop_service.dart';
import '../../domain/trip_planner/journey.dart';
import '../../domain/trip_planner/live_overlay.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/follow_providers.dart';
import '../../state/journey_on_map_provider.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../arrival_alerts/alert_bell.dart';
import '../kit/kit.dart';
import 'journey_card.dart';

/// The arrival the Board shows for [leg]'s trip at its board stop: the Board's own row (same service, same live
/// vehicles), the call nearest the leg's departure. The Board counts from today's midnight, so a journey on last
/// night's service (planned before midnight, its ride past 24:00) is moved back a day to match. Null when the Board
/// wouldn't list that bus (more than 3 hours away, or gone) or lists only another day's run of the trip.
ArrivalRow? boardArrivalFor(Journey j, RideLeg leg, GtfsRepository repo, TimeTrackFetchResult? feed, DateTime now) {
  final departs = leg.departs - secondsInServiceDay(j.serviceDate, DateTime(now.year, now.month, now.day));
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
    final gap = (r.scheduledTime.totalSeconds - departs).abs();
    // The trip runs every day: a row a day off is another day's bus.
    if (gap > AlertTracker.sameRunWindow.inSeconds) continue;
    if (bestGap == null || gap < bestGap) {
      best = r;
      bestGap = gap;
    }
  }
  return best;
}

/// [p] as a saved trip keeps it (spec §3.5): a "My location" pin is where the phone was, so it is saved as "Near"
/// the closest stop rather than as a My location that would no longer follow the phone.
Place placeForSaving(Place p, GtfsRepository? repo) {
  if (p is! PinPlace || p.label != myLocationLabel) return p;
  final nearest = repo == null
      ? null
      : NearestStopService()
          .findNearestStops(
            latitude: p.lat,
            longitude: p.lon,
            allStops: repo.stopsById.values,
            maxDistance: double.infinity,
            maxResults: 1,
          )
          .firstOrNull;
  return PinPlace(lat: p.lat, lon: p.lon, label: nearest == null ? 'Dropped pin' : 'Near ${nearest.stop.stopName}');
}

/// What the detail says when the live times break the trip (spec §3.4).
const brokenByLiveTimes = 'This trip no longer works with live times. Go back for updated options.';

/// One planned trip, leg by leg (spec §2.3): the timeline, Follow and the bell on the first ride, Show on map and
/// Save trip. Each live refresh re-times the legs and checks the trip still works (spec §3.4).
class JourneyDetailScreen extends ConsumerStatefulWidget {
  const JourneyDetailScreen({super.key, required this.journey});

  final Journey journey;

  @override
  ConsumerState<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends ConsumerState<JourneyDetailScreen> {
  /// An add is in flight: a second tap must not fire another.
  bool _saving = false;

  /// The live feed, for re-timing the alert. Paused while the steps are hidden (another page over them): unlike a watch, a manual listen is
  /// not paused with the tickers, and it would keep the feed refreshing every 30 s behind the other tabs.
  late final ProviderSubscription<TimeTrackFetchResult?> _feedSub;
  bool _feedPaused = false;

  @override
  void initState() {
    super.initState();
    // As the Board does on each refresh: a newer live time for the first ride re-times its alert (iPhone).
    _feedSub = ref.listenManual(plannerLiveFeedProvider.select((f) => f.value), (_, feed) => _retimeAlert(feed));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _retimeAlert(ref.read(plannerLiveFeedProvider).value);
      // Kept when the rider leaves for a tab without going back (Show on map, Follow bus, a notification).
      ref.read(openJourneyProvider.notifier).open(widget.journey);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paused = !TickerMode.valuesOf(context).enabled;
    if (paused == _feedPaused) return;
    _feedPaused = paused;
    if (paused) {
      _feedSub.pause();
    } else {
      _feedSub.resume();
    }
  }

  void _retimeAlert(TimeTrackFetchResult? feed) {
    final repo = ref.read(gtfsRepositoryProvider).value;
    final ride = widget.journey.legs.whereType<RideLeg>().firstOrNull;
    if (repo == null || ride == null) return;
    final arrival = boardArrivalFor(widget.journey, ride, repo, feed, ref.read(plannerClockProvider)());
    if (arrival != null) ref.read(arrivalAlertProvider.notifier).onBoardArrivals(ride.boardStopId, [arrival]);
  }

  Future<void> _save(Place draftFrom, Place draftTo) async {
    setState(() => _saving = true);
    final repo = ref.read(gtfsRepositoryProvider).value;
    final from = placeForSaving(draftFrom, repo);
    final to = placeForSaving(draftTo, repo);
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
    final repo = ref.watch(gtfsRepositoryProvider).value;
    // Refreshes every 30 s: the legs' live times, the bell and Follow with it.
    final feed = ref.watch(plannerLiveFeedProvider).value;
    final draft = ref.watch(planQueryProvider);
    final saved = ref.watch(savedTripsProvider).value ?? const <SavedTrip>[];
    final now = ref.read(plannerClockProvider)();
    final use24h = BBTime.use24h(context);
    final live = feed != null && feed.succeeded;
    final j = live ? overlayLive(widget.journey, feed, now) : widget.journey;
    // Only what is still ahead counts: no ride that has left already (the rider may be on the bus, past a change
    // that was tight), and the start checked only while the first ride hasn't left. A rider already walking to the
    // stop set out at the planned start, so the start is broken only when the live times moved it earlier than
    // planned and that earlier start has passed.
    final nowSeconds = secondsInServiceDay(j.serviceDate, now);
    final firstLeaves = j.legs.whereType<RideLeg>().firstOrNull?.departs;
    final broken = live &&
        firstTightLeg(
              j,
              notBefore: firstLeaves != null && firstLeaves >= nowSeconds
                  ? math.min(nowSeconds, widget.journey.departs)
                  : null,
              ignoreBefore: nowSeconds,
            ) !=
            null;
    String clock(int s) => BBTime.of(j.at(s), use24h: use24h);

    final from = draft.from;
    final to = draft.to;
    final isSaved = from != null && to != null && saved.any((t) => t.from == from && t.to == to);
    final firstRideAt = j.legs.indexWhere((l) => l is RideLeg);
    final firstRide = widget.journey.legs.whereType<RideLeg>().firstOrNull;
    final arrival =
        firstRide == null || repo == null ? null : boardArrivalFor(widget.journey, firstRide, repo, feed, now);
    final onSave = from == null || to == null || _saving ? null : () => _save(from, to);

    // Back from the steps closes the trip: the Plan button then opens the planner alone. The rider's back (the
    // button, the system back, the edge swipe) pops between frames; Show on map, Follow bus or a notification (a `go`)
    // removes the page while the navigator rebuilds, and leaves the trip open.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop || SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) return;
        ref.read(openJourneyProvider.notifier).close(widget.journey);
      },
      child: BBScaffold(
      body: ListView(
        children: [
          BBTopBar(
            title: 'Your trip',
            subtitle: 'Leave ${clock(j.departs)} · arrive ${clock(j.arrives)}',
            onBack: () => context.pop(),
          ),
          if (broken)
            const Padding(
              padding: EdgeInsets.fromLTRB(BBSpace.screen, 0, BBSpace.screen, BBSpace.s),
              child: _BrokenWarning(),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BBSpace.screen),
            child: BBCard(
              padding: const EdgeInsets.all(BBSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, leg) in j.legs.indexed)
                    if (leg is RideLeg) ...[
                      _RideRow(leg: leg, repo: repo, clock: clock),
                      if (i == firstRideAt && arrival != null)
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
          SizedBox(height: MediaQuery.paddingOf(context).bottom + BBSpace.l),
        ],
      ),
      ),
    );
  }
}

String _stopName(GtfsRepository? repo, String stopId) => repo?.stopsById[stopId]?.stopName ?? 'Stop $stopId';

/// "MUN Centre (1150)".
String _stopLabel(GtfsRepository? repo, String stopId) => '${_stopName(repo, stopId)} ($stopId)';

/// The live times broke a transfer or the first bus: the rider should go back for the re-planned options. A live
/// region, so a screen reader announces it when a refresh brings it up.
class _BrokenWarning extends StatelessWidget {
  const _BrokenWarning();

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(BBSpace.m),
        decoration: BoxDecoration(color: bb.colors.warnBg, borderRadius: BorderRadius.circular(BBRadius.button)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(BBIcons.warning, size: 20, color: bb.colors.warnInk)),
            const SizedBox(width: BBSpace.s),
            Expanded(child: Text(brokenByLiveTimes, style: bb.text.body.copyWith(color: bb.colors.warnInk))),
          ],
        ),
      ),
    );
  }
}

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

  /// The follow counts to this trip's boarding stop, not the Board's saved stop.
  void _follow(BuildContext context, WidgetRef ref, String vehicle) {
    ref.read(followProvider.notifier).follow(vehicle, stopId: stopId);
    context.go('/map');
  }
}

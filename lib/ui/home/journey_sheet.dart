import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/gtfs/gtfs_repository.dart';
import '../../data/realtime/timetrack_api.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/arrival_service.dart';
import '../../domain/arrival_alerts/alert_tracker.dart';
import '../../domain/trip_planner/journey.dart';
import '../../domain/trip_planner/live_overlay.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/journey_on_map_provider.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../arrival_alerts/alert_bell.dart';
import '../kit/kit.dart';
import '../trip_planner/journey_card.dart';
import 'options_sheet.dart';

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

/// What the detail says when the live times break the trip (spec §3.4).
const brokenByLiveTimes = 'This trip no longer works with live times. Go back for updated options.';

/// One planned trip in the home sheet, leg by leg (spec 2026-10-12 §3.4): its steps under [JourneySheetContent.header].
abstract final class JourneySheetContent {
  static Widget header(Journey j) => _JourneyHeader(journey: j);
  static Widget body(Journey j) => _JourneyBody(journey: j);
}

/// The journey as the live feed times it now: overlaid when the feed answered, as planned otherwise.
Journey _timed(Journey planned, TimeTrackFetchResult? feed, DateTime now) =>
    feed != null && feed.succeeded ? overlayLive(planned, feed, now) : planned;

/// Back, "Your trip", and when it leaves and arrives with the live times.
class _JourneyHeader extends ConsumerWidget {
  const _JourneyHeader({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final feed = ref.watch(plannerLiveFeedProvider).value;
    final j = _timed(journey, feed, ref.read(plannerClockProvider)());
    final use24h = BBTime.use24h(context);
    String clock(int s) => BBTime.of(j.at(s), use24h: use24h);
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.xs, 0, BBSpace.l, BBSpace.s),
      child: Row(
        children: [
          BBIconButton(
            icon: BBIcons.back,
            semanticLabel: 'Back',
            onPressed: () => ref.read(homeSheetProvider.notifier).back(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text('Your trip', style: bb.text.headline)),
                Text('Leave ${clock(j.departs)} · arrive ${clock(j.arrives)}', style: bb.text.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The timeline, Follow and the bell on the first ride, and Save trip. Each live refresh re-times the legs and checks
/// the trip still works (spec §3.4). The journey is on the map while its steps show.
class _JourneyBody extends ConsumerStatefulWidget {
  const _JourneyBody({required this.journey});

  final Journey journey;

  @override
  ConsumerState<_JourneyBody> createState() => _JourneyBodyState();
}

class _JourneyBodyState extends ConsumerState<_JourneyBody> {
  /// An add is in flight: a second tap must not fire another.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // As the Board does on each refresh: a newer live time for the first ride re-times its alert (iPhone).
    ref.listenManual(plannerLiveFeedProvider.select((f) => f.value), (_, feed) => _retimeAlert(feed));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _retimeAlert(ref.read(plannerLiveFeedProvider).value);
      // A card's tap has drawn it already; a journey opened any other way is drawn now.
      if (!identical(ref.read(journeyOnMapProvider), widget.journey)) {
        ref.read(journeyOnMapProvider.notifier).show(widget.journey);
      }
    });
  }

  void _retimeAlert(TimeTrackFetchResult? feed) {
    final repo = ref.read(gtfsRepositoryProvider).value;
    final ride = widget.journey.legs.whereType<RideLeg>().firstOrNull;
    if (repo == null || ride == null) return;
    final arrival = boardArrivalFor(widget.journey, ride, repo, feed, ref.read(plannerClockProvider)());
    if (arrival != null) ref.read(arrivalAlertProvider.notifier).onBoardArrivals(ride.boardStopId, [arrival]);
  }

  Future<void> _save(Place from, Place to) async {
    setState(() => _saving = true);
    try {
      await saveTrip(context, ref, from, to);
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
    // Kept alive under the steps, so back shows the options at once instead of planning again.
    ref.listen(planResultsProvider, (_, _) {});
    final now = ref.read(plannerClockProvider)();
    final use24h = BBTime.use24h(context);
    final live = feed != null && feed.succeeded;
    final j = _timed(widget.journey, feed, now);
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
    final firstRideAt = j.legs.indexWhere((l) => l is RideLeg);
    final firstRide = widget.journey.legs.whereType<RideLeg>().firstOrNull;
    final arrival =
        firstRide == null || repo == null ? null : boardArrivalFor(widget.journey, firstRide, repo, feed, now);
    final onSave = from == null || to == null || _saving ? null : () => _save(from, to);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  leading: Icon(BBIcons.stop, size: 22, color: bb.brandEdge),
                  children: [Text('Arrive ${clock(j.arrives)}', style: bb.text.headline)],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.l, BBSpace.screen, BBSpace.xxl),
          child: SaveTripButton(from: from, to: to, onSave: onSave),
        ),
      ],
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

  /// The follow counts to this trip's boarding stop, not the Board's saved stop. Its card takes the sheet.
  void _follow(BuildContext context, WidgetRef ref, String vehicle) {
    ref.read(followProvider.notifier).follow(vehicle, stopId: stopId);
    ref.read(homeSheetProvider.notifier).home();
  }
}

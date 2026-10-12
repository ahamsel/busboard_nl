import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../data/trip_planner/saved_trip_store.dart';
import '../../domain/location/nearest_stop_service.dart';
import '../../domain/trip_planner/journey.dart';
import '../../domain/trip_planner/place.dart';
import '../../domain/trip_planner/trip_planner.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/journey_on_map_provider.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../kit/kit.dart';
import '../trip_planner/journey_card.dart';

DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// The last day the feed has service for; [today] when it has none later.
DateTime feedEndDate(GtfsRepository? repo, DateTime today) {
  var end = _dateOnly(today);
  if (repo == null) return end;
  for (final c in repo.calendarsById.values) {
    if (c.endDate.isAfter(end)) end = _dateOnly(c.endDate);
  }
  for (final d in repo.calendarDates) {
    if (d.exceptionType == ExceptionType.added && d.date.isAfter(end)) end = _dateOnly(d.date);
  }
  return end;
}

/// "Today", "Tomorrow", or the weekday and date ("Fri, Oct 9").
String dayLabel(DateTime day, DateTime now) {
  final days = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => DateFormat('EEE, MMM d').format(day),
  };
}

/// When the next bus runs, by [dayLabel]: "tomorrow", or "on Fri, Oct 9".
String nextBusDay(DateTime t, DateTime now) {
  final d = dayLabel(t, now);
  return switch (DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays) {
    0 || 1 => d.toLowerCase(),
    _ => 'on $d',
  };
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

/// Saves [draftFrom] → [draftTo] as a trip and says how it went. Everything it needs from [ref] is taken before the
/// first await, so it is safe if the sheet goes away meanwhile.
Future<void> saveTrip(BuildContext context, WidgetRef ref, Place draftFrom, Place draftTo) async {
  final repo = ref.read(gtfsRepositoryProvider).value;
  final from = placeForSaving(draftFrom, repo);
  final to = placeForSaving(draftTo, repo);
  final store = ref.read(savedTripsProvider.notifier);
  final saved = ref.read(savedTripsProvider.future);
  try {
    final trips = await saved;
    if (!context.mounted) return;
    final same = trips.any((t) => t.from == from && t.to == to);
    if (trips.length >= maxSavedTrips && !same) {
      BBToast.show(context, 'You can save up to $maxSavedTrips trips');
      return;
    }
    final added = await store.add(SavedTrip(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: '${from.label} → ${to.label}',
          from: from,
          to: to,
        ));
    if (context.mounted) BBToast.show(context, added ? 'Saved' : 'Already saved');
  } catch (_) {
    if (context.mounted) BBToast.show(context, "Couldn't save the trip");
  }
}

/// Back from the options to what was under them: the drawn trip goes with them.
void leaveOptions(WidgetRef ref) {
  ref.read(journeyOnMapProvider.notifier).clear();
  ref.read(homeSheetProvider.notifier).back();
}

/// The ★ Save trip button for [from] → [to], filled once that trip is saved. [onSave] is null while it can't save.
class SaveTripButton extends ConsumerWidget {
  const SaveTripButton({super.key, required this.from, required this.to, required this.onSave});

  final Place? from;
  final Place? to;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedTripsProvider).value ?? const <SavedTrip>[];
    final isSaved = from != null && to != null && saved.any((t) => t.from == from && t.to == to);
    return Semantics(
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
    );
  }
}

/// Trip options for the draft, in the home sheet (spec 2026-10-12 §3.4): the destination, the start, the
/// When control, then the journeys.
abstract final class OptionsSheetContent {
  static const fromRowKey = ValueKey('plan-from');
  static const toRowKey = ValueKey('plan-to');
  static const timeButtonKey = ValueKey('plan-time');
  static const dateButtonKey = ValueKey('plan-date');
  static Widget header() => const _OptionsHeader();
  static List<Widget> slivers() => const [SliverToBoxAdapter(child: _OptionsBody())];
}

class _OptionsHeader extends ConsumerWidget {
  const _OptionsHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final draft = ref.watch(planQueryProvider);
    final to = draft.to;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.xs, 0, BBSpace.l, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BBIconButton(icon: BBIcons.back, semanticLabel: 'Back', onPressed: () => leaveOptions(ref)),
              Expanded(
                child: BBPressable(
                  key: OptionsSheetContent.toRowKey,
                  semanticLabel: 'Destination, ${to == null ? 'not chosen' : to.label}. Change',
                  onTap: () => context.push('/search'),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        to == null ? 'Choose a destination' : 'To ${to.label}',
                        style: to == null ? bb.text.headline.copyWith(color: bb.colors.muted) : bb.text.headline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: BBSpace.m),
            child: Row(
              children: [
                Expanded(
                  child: _EndRow(
                    key: OptionsSheetContent.fromRowKey,
                    caption: 'From',
                    place: draft.from,
                    placeholder: 'Choose a start',
                    onTap: () => context.push('/search?end=from'),
                  ),
                ),
                const SizedBox(width: BBSpace.s),
                BBIconButton(
                  icon: BBIcons.swap,
                  semanticLabel: 'Swap start and destination',
                  onPressed: ref.read(planQueryProvider.notifier).swap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionsBody extends ConsumerStatefulWidget {
  const _OptionsBody();

  @override
  ConsumerState<_OptionsBody> createState() => _OptionsBodyState();
}

class _OptionsBodyState extends ConsumerState<_OptionsBody> {
  /// The form changed and the results on screen are for the old one. While only the live times refresh (every
  /// 30 s) the old results stay up instead of flashing the loading dots.
  bool _formChanged = false;

  /// An add is in flight: a second tap must not fire another.
  bool _saving = false;

  /// What this sheet last drew: the first journey's rides and walks, for the ends it was planned for. A live
  /// refresh of the same trip leaves the map (and its camera) alone; a new trip replaces it.
  (Place?, Place?, String)? _drawn;

  @override
  void initState() {
    super.initState();
    // Back from a journey's steps, or results already in: draw the first journey again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _drawFirst(ref.read(planResultsProvider).value);
    });
  }

  static (Place?, Place?, String) _signature(Journey j, PlanDraft draft) => (
        draft.from,
        draft.to,
        [
          j.serviceDate.toIso8601String(),
          for (final l in j.legs)
            switch (l) {
              RideLeg() => 'ride ${l.tripId} ${l.boardStopId}-${l.alightStopId}',
              WalkLeg() => 'walk ${l.fromStopId}-${l.toStopId}',
            },
        ].join('|'),
      );

  void _drawFirst(PlanOutcome? outcome) {
    if (ref.read(homeSheetProvider) is! OptionsSheet) return;
    final onMap = ref.read(journeyOnMapProvider.notifier);
    final first = outcome is PlanFound ? outcome.journeys.firstOrNull : null;
    if (first == null) {
      // The trip it drew no longer stands for this form.
      if (_drawn != null) onMap.clear();
      _drawn = null;
      return;
    }
    final signature = _signature(first, ref.read(planQueryProvider));
    if (signature == _drawn) return;
    _drawn = signature;
    onMap.show(first);
  }

  Future<void> _pickTime(DateTime current) async {
    final t = await showBBTimePicker(context, initial: current);
    if (t != null && mounted) ref.read(planQueryProvider.notifier).setTime(t);
  }

  Future<void> _pickDate(DateTime current, DateTime now, GtfsRepository? repo) async {
    final d = await showBBDatePicker(context, initial: current, first: now, last: feedEndDate(repo, now));
    if (d != null && mounted) ref.read(planQueryProvider.notifier).setTime(d);
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
    final draft = ref.watch(planQueryProvider);
    // Watched so the feed is loaded (and kept) for the date range.
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final results = ref.watch(planResultsProvider);
    ref.listen(planQueryProvider, (_, _) => _formChanged = true);
    ref.listen<AsyncValue<PlanOutcome?>>(planResultsProvider, (_, next) => _drawFirst(next.value));
    if (!results.isLoading) _formChanged = false;
    final now = ref.read(plannerClockProvider)();
    final when = draft.usesDefaultTime ? ref.watch(planDefaultTimeProvider) : draft.time ?? now;
    final use24h = BBTime.use24h(context);
    final q = ref.read(planQueryProvider.notifier);
    final from = draft.from;
    final to = draft.to;

    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.xs, BBSpace.l, BBSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BBSegmented<PlanMode>(
            segments: const [
              BBSegment(value: PlanMode.leaveNow, label: 'Leave now'),
              BBSegment(value: PlanMode.leaveBy, label: 'Leave by'),
              BBSegment(value: PlanMode.arriveBy, label: 'Arrive by'),
            ],
            selected: draft.mode,
            onChanged: q.setMode,
          ),
          if (draft.mode != PlanMode.leaveNow) ...[
            const SizedBox(height: BBSpace.m),
            _FieldButton(
              key: OptionsSheetContent.timeButtonKey,
              icon: BBIcons.schedule,
              label: BBTime.of(when, use24h: use24h),
              semanticLabel: 'Time, ${BBTime.of(when, use24h: use24h)}',
              onTap: () => _pickTime(when),
            ),
            const SizedBox(height: BBSpace.s),
            _FieldButton(
              key: OptionsSheetContent.dateButtonKey,
              icon: BBIcons.calendar,
              label: dayLabel(when, now),
              semanticLabel: 'Date, ${dayLabel(when, now)}',
              onTap: () => _pickDate(when, now, repo),
            ),
          ],
          const SizedBox(height: BBSpace.l),
          ..._results(context, results, now),
          if (from != null && to != null) ...[
            const SizedBox(height: BBSpace.l),
            SaveTripButton(from: from, to: to, onSave: _saving ? null : () => _save(from, to)),
          ],
        ],
      ),
    );
  }

  List<Widget> _results(BuildContext context, AsyncValue<PlanOutcome?> results, DateTime now) {
    final bb = context.bb;
    // A new form loads afresh; a live refresh (or Riverpod's retry after a failure) keeps what is shown.
    final replanning = results.isLoading && _formChanged;
    if (results.hasError && !replanning) {
      return [
        const BBEmptyState(
          icon: BBIcons.warning,
          title: "Couldn't plan that trip",
          message: 'Try again in a moment.',
        ),
      ];
    }
    if (replanning || (results.isLoading && !results.hasValue)) {
      return [
        const Padding(
          padding: EdgeInsets.all(BBSpace.xxl),
          child: Center(child: BBLoading()),
        ),
      ];
    }
    const noJourney = BBEmptyState(icon: BBIcons.noService, title: 'No buses get you there at that time');
    return switch (results.value) {
      null => [
        Padding(
          padding: const EdgeInsets.all(BBSpace.xxl),
          child: Text(
            "Choose where you're going",
            textAlign: TextAlign.center,
            style: bb.text.body.copyWith(color: bb.colors.muted),
          ),
        ),
      ],
      PlanFound(:final journeys) when journeys.isEmpty => [noJourney],
      PlanFound(:final journeys) => [
        for (final (i, j) in journeys.indexed) ...[
          if (i > 0) const SizedBox(height: BBSpace.s),
          JourneyCard(
            journey: j,
            onTap: () {
              ref.read(journeyOnMapProvider.notifier).show(j);
              ref.read(homeSheetProvider.notifier).open(JourneySheet(j));
            },
          ),
        ],
      ],
      PlanNoJourney(:final nextDeparture, :final firstArrival) => [
        BBEmptyState(
          icon: BBIcons.noService,
          title: 'No buses get you there at that time',
          message: nextDeparture != null
              ? 'The next bus that gets you there leaves ${nextBusDay(nextDeparture, now)} at '
                    '${BBTime.of(nextDeparture, use24h: BBTime.use24h(context))}'
              : firstArrival != null
              ? 'The earliest you can get there is ${BBTime.of(firstArrival, use24h: BBTime.use24h(context))}'
              : null,
        ),
      ],
      PlanTooFar(:final fromEnd) => [
        BBEmptyState(
          icon: BBIcons.warning,
          title: 'Too far from a bus stop',
          message: 'Pick a closer point for your ${fromEnd ? 'start' : 'destination'}.',
        ),
      ],
    };
  }
}

/// The From row: the place's name, or what to choose, in the muted style.
class _EndRow extends StatelessWidget {
  const _EndRow({
    super.key,
    required this.caption,
    required this.place,
    required this.placeholder,
    required this.onTap,
  });

  final String caption;
  final Place? place;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final p = place;
    return BBPressable(
      onTap: onTap,
      semanticLabel: '$caption: ${p == null ? 'not chosen' : p.label}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BBSpace.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(caption, style: bb.text.caption),
              Text(
                p?.label ?? placeholder,
                style: p == null ? bb.text.body.copyWith(color: bb.colors.muted) : bb.text.headline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A form value that opens a picker: the time, or the day.
class _FieldButton extends StatelessWidget {
  const _FieldButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return BBPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.s),
        decoration: BoxDecoration(color: bb.colors.surfaceSunken, borderRadius: BorderRadius.circular(BBRadius.button)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: bb.colors.muted),
            const SizedBox(width: BBSpace.s),
            Expanded(
              child: Text(label, style: bb.text.label.copyWith(color: bb.colors.ink)),
            ),
            Icon(BBIcons.chevronDown, size: 18, color: bb.colors.muted),
          ],
        ),
      ),
    );
  }
}

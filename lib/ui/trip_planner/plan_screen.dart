import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../domain/trip_planner/place.dart';
import '../../domain/trip_planner/trip_planner.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../kit/kit.dart';
import 'journey_card.dart';
import 'place_picker_sheet.dart';
import 'saved_trips_section.dart';

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

/// The Plan tab (spec §2.2): saved trips, then From / To / When, then the results.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  static const fromRowKey = ValueKey('plan-from');
  static const toRowKey = ValueKey('plan-to');
  static const timeButtonKey = ValueKey('plan-time');
  static const dateButtonKey = ValueKey('plan-date');

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  /// The form changed and the results on screen are for the old one. While only the live times refresh (every
  /// 30 s) the old results stay up instead of flashing the loading dots.
  bool _formChanged = false;

  Future<void> _pick({required bool forFrom}) async {
    final pick = await showPlacePicker(context, forFrom: forFrom);
    if (!mounted || pick == null) return;
    final q = ref.read(planQueryProvider.notifier);
    switch (pick) {
      case PickedPlace(:final place):
        forFrom ? q.setFrom(place) : q.setTo(place);
      case PickOnMap():
        context.go('/map?pick=${forFrom ? 'from' : 'to'}');
    }
  }

  Future<void> _pickTime(DateTime current) async {
    final t = await showBBTimePicker(context, initial: current);
    if (t != null) ref.read(planQueryProvider.notifier).setTime(t);
  }

  Future<void> _pickDate(DateTime current, DateTime now, GtfsRepository? repo) async {
    final d = await showBBDatePicker(context, initial: current, first: now, last: feedEndDate(repo, now));
    if (d != null) ref.read(planQueryProvider.notifier).setTime(d);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(planQueryProvider);
    // Watched so the feed is loaded (and kept) for the place picker and the date range.
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final results = ref.watch(planResultsProvider);
    ref.listen(planQueryProvider, (_, _) => _formChanged = true);
    if (!results.isLoading) _formChanged = false;
    final now = ref.read(plannerClockProvider)();
    final when = draft.usesDefaultTime ? ref.watch(planDefaultTimeProvider) : draft.time ?? now;
    final use24h = BBTime.use24h(context);
    final q = ref.read(planQueryProvider.notifier);

    return BBScaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: BBTopBar(
              title: 'Plan a trip',
              large: true,
              actions: [
                BBIconButton(
                  icon: BBIcons.settings,
                  semanticLabel: 'Settings',
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: BBSpace.screen),
            sliver: SliverList.list(
              children: [
                const SavedTripsSection(),
                BBCard(
                  padding: const EdgeInsets.all(BBSpace.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _EndRow(
                                  key: PlanScreen.fromRowKey,
                                  caption: 'From',
                                  place: draft.from,
                                  placeholder: 'Choose a starting point',
                                  onTap: () => _pick(forFrom: true),
                                ),
                                const BBDivider(),
                                _EndRow(
                                  key: PlanScreen.toRowKey,
                                  caption: 'To',
                                  place: draft.to,
                                  placeholder: 'Choose a destination',
                                  onTap: () => _pick(forFrom: false),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: BBSpace.s),
                          BBIconButton(
                            icon: BBIcons.swap,
                            semanticLabel: 'Swap start and destination',
                            onPressed: q.swap,
                          ),
                        ],
                      ),
                      const SizedBox(height: BBSpace.m),
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
                          key: PlanScreen.timeButtonKey,
                          icon: BBIcons.schedule,
                          label: BBTime.of(when, use24h: use24h),
                          semanticLabel: 'Time, ${BBTime.of(when, use24h: use24h)}',
                          onTap: () => _pickTime(when),
                        ),
                        const SizedBox(height: BBSpace.s),
                        _FieldButton(
                          key: PlanScreen.dateButtonKey,
                          icon: BBIcons.calendar,
                          label: dayLabel(when, now),
                          semanticLabel: 'Date, ${dayLabel(when, now)}',
                          onTap: () => _pickDate(when, now, repo),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: BBSpace.l),
              ],
            ),
          ),
          ..._results(context, results, now, missingTo: draft.to == null),
          SliverToBoxAdapter(child: SizedBox(height: BBNavBar.reservedHeight(context) + BBSpace.l)),
        ],
      ),
    );
  }

  List<Widget> _results(
    BuildContext context,
    AsyncValue<PlanOutcome?> results,
    DateTime now, {
    required bool missingTo,
  }) {
    final bb = context.bb;
    Widget box(Widget child) => SliverToBoxAdapter(child: child);
    // A new form loads afresh; a live refresh (or Riverpod's retry after a failure) keeps what is shown.
    final replanning = results.isLoading && _formChanged;
    if (results.hasError && !replanning) {
      return [
        box(
          const BBEmptyState(
            icon: BBIcons.warning,
            title: "Couldn't plan that trip",
            message: 'Try again in a moment.',
          ),
        ),
      ];
    }
    if (replanning || (results.isLoading && !results.hasValue)) {
      return [
        box(
          const Padding(
            padding: EdgeInsets.all(BBSpace.xxl),
            child: Center(child: BBLoading()),
          ),
        ),
      ];
    }
    final noJourney = box(const BBEmptyState(icon: BBIcons.noService, title: 'No buses get you there at that time'));
    return switch (results.value) {
      null => [
        box(
          Padding(
            padding: const EdgeInsets.all(BBSpace.xxl),
            child: Text(
              // Whichever end is missing: the destination first, else the start.
              missingTo ? "Choose where you're going" : "Choose where you're starting",
              textAlign: TextAlign.center,
              style: bb.text.body.copyWith(color: bb.colors.muted),
            ),
          ),
        ),
      ],
      PlanFound(:final journeys) when journeys.isEmpty => [noJourney],
      PlanFound(:final journeys) => [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: BBSpace.screen),
          sliver: SliverList.separated(
            itemCount: journeys.length,
            separatorBuilder: (_, _) => const SizedBox(height: BBSpace.s),
            itemBuilder: (context, i) => JourneyCard(
              journey: journeys[i],
              onTap: () => context.push('/plan/journey', extra: journeys[i]),
            ),
          ),
        ),
      ],
      PlanNoJourney(:final nextDeparture, :final firstArrival) => [
        box(
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
        ),
      ],
      PlanTooFar(:final fromEnd) => [
        box(
          BBEmptyState(
            icon: BBIcons.warning,
            title: 'Too far from a bus stop',
            message: 'Pick a closer point for your ${fromEnd ? 'start' : 'destination'}.',
          ),
        ),
      ],
    };
  }
}

/// The From or To row: the place's name, or what to choose, in the muted style.
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

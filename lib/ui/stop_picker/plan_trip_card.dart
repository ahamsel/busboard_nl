import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/trip_planner/saved_trip_store.dart';
import '../../routing/push_once.dart';
import '../../state/trip_planner_providers.dart';
import '../kit/kit.dart';
import '../shell/top_actions.dart';
import '../trip_planner/saved_trips_section.dart';

/// The stop picker's way into the trip planner, under the Last stop card: a header line that opens the planner as
/// the Plan button does, then the rider's first saved trips, each with its next bus, and "All saved trips" when
/// there are more. With nothing saved it is the header line alone.
class PlanTripCard extends ConsumerWidget {
  const PlanTripCard({super.key});

  static const headerKey = ValueKey('plan-trip-card');
  static const allKey = ValueKey('plan-trip-card-all');
  static Key tripKey(String id) => ValueKey('plan-trip-card-trip-$id');

  /// The saved trips the card lists; the planner has the rest.
  static const maxTrips = 3;

  /// The icon tile's size, and so the indent that lines the trips up under the title.
  static const _tile = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final trips = ref.watch(savedTripsProvider).value ?? const <SavedTrip>[];
    const indent = BBSpace.m + _tile + BBSpace.m;

    // One guard for every line: two quick taps, on one line or two, open one planner.
    return PushOnce(
      builder: (context, push) => DecoratedBox(
        decoration: bb.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BBPressable(
              key: headerKey,
              semanticLabel: 'Plan a trip. Leave or arrive by any time',
              onTap: () => TopActions.openPlanner(context, ref, push),
              // The Last stop card's look and padding (BBCard's), so the two read as a pair.
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: 10),
                child: Row(children: [
                  const BBIconTile(icon: BBIcons.plan, size: _tile),
                  const SizedBox(width: BBSpace.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Plan a trip', style: bb.text.headline),
                      Text('Leave or arrive by any time', style: bb.text.caption.copyWith(color: bb.colors.muted)),
                    ]),
                  ),
                  Icon(BBIcons.chevronRight, color: bb.colors.muted),
                ]),
              ),
            ),
            if (trips.isNotEmpty) ...[
              const BBDivider(indent: indent),
              for (final trip in trips.take(maxTrips))
                _TripLine(
                  key: tripKey(trip.id),
                  trip: trip,
                  indent: indent,
                  onTap: () => push('/plan', then: () {
                    ref.read(planQueryProvider.notifier).setTrip(trip.from, trip.to);
                    // A new plan: a trip left open no longer comes back from the Plan button.
                    ref.read(openJourneyProvider.notifier).close();
                  }),
                ),
              if (trips.length > maxTrips)
                _Line(
                  key: allKey,
                  indent: indent,
                  semanticLabel: 'All saved trips',
                  onTap: () => push('/plan'),
                  child: Row(children: [
                    Expanded(child: Text('All saved trips', style: bb.text.label.copyWith(color: bb.colors.brandInk))),
                    Icon(BBIcons.chevronRight, color: bb.colors.muted),
                  ]),
                ),
              const SizedBox(height: BBSpace.xs),
            ],
          ],
        ),
      ),
    );
  }
}

/// One tappable line under the header, lined up with its title, at least 44 pt tall.
class _Line extends StatelessWidget {
  const _Line({super.key, required this.indent, required this.semanticLabel, required this.onTap, required this.child});

  final double indent;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => BBPressable(
        semanticLabel: semanticLabel,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(indent, BBSpace.s, BBSpace.m, BBSpace.s),
            child: Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, child: child),
          ),
        ),
      );
}

/// A saved trip: its name, then its next bus at the right, as its card on the planner reads it.
class _TripLine extends ConsumerWidget {
  const _TripLine({super.key, required this.trip, required this.indent, required this.onTap});

  final SavedTrip trip;
  final double indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final next = watchSavedTripDepartures(ref, trip.id);
    final use24h = BBTime.use24h(context);
    // Said "Home to MUN Centre", not "Home right arrow MUN Centre".
    final spoken = 'Saved trip ${trip.name.replaceAll(' → ', ' to ')}';

    final String label;
    final Widget when;
    if (next == null) {
      label = '$spoken, loading departures';
      when = const SizedBox(
        width: 56,
        child: BBSkeleton(kind: BBSkeletonKind.line, count: 1, label: 'Loading departures'),
      );
    } else if (next.isEmpty) {
      label = '$spoken, ${savedTripNoBuses.toLowerCase()}';
      when = Text(savedTripNoBuses, textAlign: TextAlign.end, style: bb.text.body.copyWith(color: bb.colors.muted));
    } else {
      final first = next.first;
      final time = BBTime.of(first.time, use24h: use24h);
      final live = first.ride.live;
      label = '$spoken, next bus $time${live ? ', live' : ''}';
      when = Text(
        '$time${live ? ' · live' : ''}',
        textAlign: TextAlign.end,
        style: bb.text.label.copyWith(color: live ? bb.colors.liveInk : bb.colors.ink),
      );
    }

    final name = Text(trip.name, style: bb.text.body);
    return _Line(
      indent: indent,
      semanticLabel: label,
      onTap: onTap,
      // One line, the bus at the right; where large text leaves no room for both, the bus goes under the name.
      child: LayoutBuilder(builder: (context, box) {
        final nameWidth = TopActions.textWidth(context, trip.name, bb.text.body);
        final whenWidth = when is Text ? TopActions.textWidth(context, when.data!, when.style!) : 56.0;
        if (nameWidth + BBSpace.m + whenWidth <= box.maxWidth) {
          return Row(children: [Expanded(child: name), const SizedBox(width: BBSpace.m), when]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [name, const SizedBox(height: BBSpace.xs), Align(alignment: AlignmentDirectional.centerEnd, child: when)],
        );
      }),
    );
  }
}

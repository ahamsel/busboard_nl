import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/trip_planner/saved_trip_store.dart';
import '../../domain/trip_planner/journey.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../kit/kit.dart';
import 'journey_card.dart';

/// The longest name a saved trip can be given.
const savedTripNameMax = 40;

/// The rider's saved trips, above the planner (spec §2.2): each with its next departures, live.
/// Shows nothing until there is a saved trip.
class SavedTripsSection extends ConsumerWidget {
  const SavedTripsSection({super.key});

  /// The card's "More" button, for tests.
  static Key moreKey(String id) => ValueKey('saved-trip-more-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(savedTripsProvider).value ?? const <SavedTrip>[];
    if (trips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BBSectionHeader(title: 'Saved trips'),
        const SizedBox(height: BBSpace.s),
        for (final trip in trips) ...[
          _SavedTripCard(key: ValueKey('saved-trip-${trip.id}'), trip: trip),
          const SizedBox(height: BBSpace.s),
        ],
        const SizedBox(height: BBSpace.s),
      ],
    );
  }
}

/// The clock time without AM / PM ("8:12"): the card shows the next few buses, all within hours of now.
String _clock(DateTime t, bool use24h) =>
    BBTime.of(t, use24h: use24h).replaceAll(RegExp(r'\s?[AP]M$'), '');

/// The first ride of [j]; null for a journey that is only walking.
RideLeg? _firstRide(Journey j) => j.legs.whereType<RideLeg>().firstOrNull;

/// One of a saved trip's next buses: when its first ride leaves, and that ride.
typedef SavedTripDeparture = ({DateTime time, RideLeg ride});

/// What a saved trip says once no bus is left today, on its card here and its line on the stop picker.
const savedTripNoBuses = 'No more buses today';

/// The buses the card lists: each journey's first ride, by when it leaves, earliest first. Journeys that share
/// a first bus, or leave at the same time on the same route, count once; at most three.
@visibleForTesting
List<SavedTripDeparture> savedTripDepartures(Iterable<Journey> journeys) {
  final all = [
    for (final j in journeys)
      if (_firstRide(j) case final ride?) (time: j.at(ride.departs), ride: ride),
  ]..sort((a, b) => a.time.compareTo(b.time));
  final out = <SavedTripDeparture>[];
  for (final d in all) {
    if (out.any((o) => o.ride.tripId == d.ride.tripId || (o.time == d.time && o.ride.routeId == d.ride.routeId))) continue;
    out.add(d);
    if (out.length == 3) break;
  }
  return out;
}

/// The saved trip [id]'s next buses, as [savedTripDepartures] lists them, live: null while they first load, empty
/// once there are no more today. Its card on the planner and its line on the stop picker both read them here.
List<SavedTripDeparture>? watchSavedTripDepartures(WidgetRef ref, String id) {
  final next = ref.watch(savedTripNextProvider(id));
  if (next.isLoading && !next.hasValue) return null;
  return savedTripDepartures(next.value ?? const <Journey>[]);
}

class _SavedTripCard extends ConsumerWidget {
  const _SavedTripCard({super.key, required this.trip});

  final SavedTrip trip;

  Future<void> _more(BuildContext context, WidgetRef ref) async {
    final action = await _editTrip(context, trip);
    if (action == null || !context.mounted) return;
    final saved = ref.read(savedTripsProvider.notifier);
    switch (action) {
      case _Rename(:final name):
        await saved.rename(trip.id, name);
      case _Remove():
        final confirmed = await BBDialog.show<bool>(
          context,
          title: 'Remove this saved trip?',
          message: trip.name,
          actions: const [
            BBDialogAction(label: 'Cancel', value: false),
            BBDialogAction(label: 'Remove', value: true, primary: true),
          ],
        );
        if (confirmed == true) await saved.remove(trip.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final next = watchSavedTripDepartures(ref, trip.id);
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final use24h = BBTime.use24h(context);

    // Each departure is its first ride's: when the bus leaves, not when the rider sets out.
    final rides = [
      for (final d in next ?? const <SavedTripDeparture>[]) (time: _clock(d.time, use24h), ride: d.ride),
    ];

    final String label;
    final Widget departures;
    if (next == null) {
      label = 'Saved trip ${trip.name}, loading departures';
      departures = const BBSkeleton(
        kind: BBSkeletonKind.line,
        count: 1,
        label: 'Loading departures',
      );
    } else if (rides.isEmpty) {
      label = 'Saved trip ${trip.name}, no more buses today';
      departures = Text(
        savedTripNoBuses,
        style: bb.text.body.copyWith(color: bb.colors.muted),
      );
    } else {
      final first = rides.first;
      final route = routeNameOf(first.ride.routeId, repo);
      final live = first.ride.live;
      label =
          'Saved trip ${trip.name}, next bus ${first.time}, route $route${live ? ', live' : ''}';
      departures = Wrap(
        spacing: BBSpace.s,
        runSpacing: BBSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${first.time} · $route${live ? ' · live' : ''}',
            style: bb.text.label.copyWith(
              color: live ? bb.colors.liveInk : bb.colors.ink,
            ),
          ),
          if (rides.length > 1)
            Text(
              rides.skip(1).map((r) => r.time).join(', '),
              style: bb.text.body.copyWith(color: bb.colors.muted),
            ),
        ],
      );
    }

    return GestureDetector(
      onLongPress: () => _more(context, ref),
      child: DecoratedBox(
        decoration: bb.card(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BBPressable(
                semanticLabel: label,
                onTap: () => ref
                    .read(planQueryProvider.notifier)
                    .setTrip(trip.from, trip.to),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BBSpace.m,
                    BBSpace.m,
                    0,
                    BBSpace.m,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(trip.name, style: bb.text.title),
                      const SizedBox(height: BBSpace.xs),
                      departures,
                    ],
                  ),
                ),
              ),
            ),
            BBIconButton(
              key: SavedTripsSection.moreKey(trip.id),
              icon: BBIcons.more,
              semanticLabel: 'More, ${trip.name}',
              onPressed: () => _more(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

sealed class _EditAction {}

class _Rename extends _EditAction {
  _Rename(this.name);
  final String name;
}

class _Remove extends _EditAction {}

/// Rename or Remove for [trip]. A blank name keeps the old one; longer than [savedTripNameMax] can't be typed.
Future<_EditAction?> _editTrip(BuildContext context, SavedTrip trip) async {
  var text = trip.name;
  final picked = await BBDialog.show<int>(
    context,
    title: 'Saved trip',
    content: _NameField(initial: trip.name, onChanged: (v) => text = v),
    actions: const [
      BBDialogAction(label: 'Cancel', value: 0),
      BBDialogAction(label: 'Remove', value: 1),
      BBDialogAction(label: 'Rename', value: 2, primary: true),
    ],
  );
  return switch (picked) {
    1 => _Remove(),
    2 => _Rename(text.trim().isEmpty ? trip.name : text.trim()),
    _ => null,
  };
}

/// The name field, with its own controller (the dialog is still on screen while it closes).
class _NameField extends StatefulWidget {
  const _NameField({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BBTextField(
    controller: _controller,
    hint: 'Trip name',
    // The field opens on the current name: without a label it would be announced by that value alone.
    semanticLabel: 'Trip name',
    autofocus: true,
    onChanged: widget.onChanged,
    inputFormatters: [LengthLimitingTextInputFormatter(savedTripNameMax)],
  );
}

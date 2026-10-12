import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/trip_planner/journey.dart';
import '../domain/trip_planner/place.dart';
import 'trip_planner_providers.dart';

/// The planned journey the map draws (spec §2.3), or null for none.
class JourneyOnMapNotifier extends Notifier<Journey?> {
  Place? _from;
  Place? _to;

  @override
  Journey? build() => null;

  /// The trip's start, as planned when the journey was shown: a walk with no stop at its start begins here.
  Place? get from => _from;

  /// The trip's end, as planned when the journey was shown: a walk with no stop at its end finishes here.
  Place? get to => _to;

  /// Shows [j], with the ends it was planned for (the trip options' draft, now).
  void show(Journey j) {
    final draft = ref.read(planQueryProvider);
    _from = draft.from;
    _to = draft.to;
    state = j;
  }

  void clear() {
    _from = null;
    _to = null;
    state = null;
  }
}

final journeyOnMapProvider = NotifierProvider<JourneyOnMapNotifier, Journey?>(JourneyOnMapNotifier.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_request_provider.dart';

/// Which end of the trip the next tap on the map chooses (spec 2026-10-12 §3.3), or null.
enum MapPick { from, to }

class MapPickNotifier extends Notifier<MapPick?> {
  /// For a destination pick: whether it keeps the trip's start, mode and time (it was started from the trip
  /// options' own search) rather than starting a fresh trip (from Where to?). Ruling 14.
  bool keepStart = false;

  @override
  MapPick? build() => null;
  void start(MapPick end, {bool keepStart = false}) {
    this.keepStart = keepStart;
    state = end;
    // Choosing happens on the map, even when a pick was already pending.
    ref.read(mapRequestProvider.notifier).request();
  }

  void clear() => state = null;
}

final mapPickProvider = NotifierProvider<MapPickNotifier, MapPick?>(MapPickNotifier.new);

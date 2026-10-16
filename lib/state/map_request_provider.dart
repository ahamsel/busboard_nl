import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts the times something asked to be shown on the Map tab (spec 2026-10-15 §2.3): a follow, a trip's options or
/// steps, choosing on the map. The home shell switches to the Map on every request, so asking again for what is
/// already set (the same bus, options already open, a pick already pending) still brings the rider to it, which a
/// listener on the state itself could not do.
final mapRequestProvider = NotifierProvider<MapRequestNotifier, int>(MapRequestNotifier.new);

class MapRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Something asked to be shown on the Map.
  void request() => state++;
}

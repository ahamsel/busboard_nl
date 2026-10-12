import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which end of the trip the next tap on the map chooses (spec 2026-10-12 §3.3), or null.
enum MapPick { from, to }

class MapPickNotifier extends Notifier<MapPick?> {
  @override
  MapPick? build() => null;
  void start(MapPick end) => state = end;
  void clear() => state = null;
}

final mapPickProvider = NotifierProvider<MapPickNotifier, MapPick?>(MapPickNotifier.new);

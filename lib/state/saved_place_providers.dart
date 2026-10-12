import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trip_planner/saved_place_store.dart';
import '../domain/trip_planner/place.dart';

final savedPlaceStoreProvider = Provider<SavedPlaceStore>((ref) => SavedPlaceStore());
final recentPlaceStoreProvider = Provider<RecentPlaceStore>((ref) => RecentPlaceStore());

/// Changes run one at a time (the stores read, change and write the whole list), like saved trips.
mixin _Serial {
  Future<void> _queue = Future.value();
  Future<T> serial<T>(Future<T> Function() op) {
    final run = _queue.catchError((_) {}).then((_) => op());
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

class SavedPlacesNotifier extends AsyncNotifier<List<SavedPlace>> with _Serial {
  SavedPlaceStore get _store => ref.read(savedPlaceStoreProvider);
  @override
  Future<List<SavedPlace>> build() => _store.read();

  Future<bool> put(SavedPlace p) => serial(() async {
        final ok = await _store.put(p);
        state = AsyncData(await _store.read());
        return ok;
      });

  Future<void> remove(String id) => serial(() async {
        await _store.remove(id);
        state = AsyncData(await _store.read());
      });
}

class RecentPlacesNotifier extends AsyncNotifier<List<Place>> with _Serial {
  RecentPlaceStore get _store => ref.read(recentPlaceStoreProvider);
  @override
  Future<List<Place>> build() => _store.read();

  Future<void> push(Place p) => serial(() async {
        await _store.push(p);
        state = AsyncData(await _store.read());
      });
}

final savedPlacesProvider = AsyncNotifierProvider<SavedPlacesNotifier, List<SavedPlace>>(SavedPlacesNotifier.new);
final recentPlacesProvider = AsyncNotifierProvider<RecentPlacesNotifier, List<Place>>(RecentPlacesNotifier.new);

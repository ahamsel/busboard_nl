import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  final mun = StopPlace(stopId: '1150', name: 'MUN Centre');
  final pin = PinPlace(lat: 47.56, lon: -52.71, label: 'Dropped pin');

  test('put, read back, replace by id', () async {
    final s = SavedPlaceStore();
    expect(await s.put(SavedPlace(id: 'a', name: 'MUN', icon: SavedPlaceIcon.school, place: mun)), isTrue);
    expect(await s.put(SavedPlace(id: 'a', name: 'Campus', icon: SavedPlaceIcon.school, place: mun)), isTrue);
    final all = await s.read();
    expect(all, hasLength(1));
    expect(all.single.name, 'Campus');
    expect(all.single.place, mun);
  });

  test('a second Home demotes the first to a star', () async {
    final s = SavedPlaceStore();
    await s.put(SavedPlace(id: 'a', name: 'Home', icon: SavedPlaceIcon.home, place: mun));
    await s.put(SavedPlace(id: 'b', name: 'New home', icon: SavedPlaceIcon.home, place: pin));
    final byId = {for (final p in await s.read()) p.id: p};
    expect(byId['a']!.icon, SavedPlaceIcon.star);
    expect(byId['b']!.icon, SavedPlaceIcon.home);
  });

  test('full list refuses a new id', () async {
    final s = SavedPlaceStore();
    for (var i = 0; i < maxSavedPlaces; i++) {
      await s.put(SavedPlace(id: '$i', name: '$i', icon: SavedPlaceIcon.star, place: StopPlace(stopId: '$i', name: '$i')));
    }
    expect(await s.put(SavedPlace(id: 'x', name: 'x', icon: SavedPlaceIcon.star, place: mun)), isFalse);
  });

  test('remove', () async {
    final s = SavedPlaceStore();
    await s.put(SavedPlace(id: 'a', name: 'MUN', icon: SavedPlaceIcon.star, place: mun));
    await s.remove('a');
    expect(await s.read(), isEmpty);
  });

  test('corrupt or unknown entries are skipped (Review Focus 5)', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('saved_places.v1', 'not json');
    expect(await SavedPlaceStore().read(), isEmpty);
    await prefs.setString('saved_places.v1',
        '[{"id":"a","name":"x","icon":"home","place":{"kind":"spaceship"}},{"id":"b","name":"MUN","icon":"nope","place":{"kind":"stop","stopId":"1150","name":"MUN Centre"}}]');
    final all = await SavedPlaceStore().read();
    expect(all.map((p) => p.id), ['b']);
    expect(all.single.icon, SavedPlaceIcon.star); // unknown icon falls back to star
    await prefs.setString('recent_places.v1', '{"oops":1}');
    expect(await RecentPlaceStore().read(), isEmpty);
  });

  test('recent: newest first, deduplicated, at most 10', () async {
    final r = RecentPlaceStore();
    for (var i = 0; i < 12; i++) {
      await r.push(StopPlace(stopId: '$i', name: '$i'));
    }
    await r.push(StopPlace(stopId: '5', name: '5'));
    final all = await r.read();
    expect(all, hasLength(maxRecentPlaces));
    expect((all.first as StopPlace).stopId, '5');
    expect(all.whereType<StopPlace>().where((p) => p.stopId == '5'), hasLength(1));
  });
}

import 'dart:convert';

import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  SavedTrip trip(String id, String a, String b) =>
      SavedTrip(id: id, name: '$a → $b', from: StopPlace(stopId: a, name: a), to: StopPlace(stopId: b, name: b));

  test('add, read, rename, remove; a pin end survives the round trip', () async {
    final store = SavedTripStore();
    expect(await store.add(trip('1', '1150', '1600')), isTrue);
    final pin = PinPlace(lat: 47.56, lon: -52.71, label: 'Home');
    expect(await store.add(SavedTrip(id: '2', name: 'Home → MUN', from: pin, to: StopPlace(stopId: '1150', name: 'MUN Centre'))), isTrue);
    final read = await store.read();
    expect(read.map((t) => t.name), ['1150 → 1600', 'Home → MUN']);
    expect(read[1].from, pin);
    expect(read[1].from.label, 'Home');
    await store.rename('1', 'Downtown → Avalon');
    expect((await store.read()).first.name, 'Downtown → Avalon');
    await store.remove('1');
    expect((await store.read()).single.id, '2');
  });

  test('the same ends twice is refused; so is an 11th trip', () async {
    final store = SavedTripStore();
    expect(await store.add(trip('1', 'A', 'B')), isTrue);
    expect(await store.add(trip('x', 'A', 'B')), isFalse);
    expect(await store.add(trip('r', 'B', 'A')), isTrue); // the way back is a different trip
    for (var i = 3; i <= maxSavedTrips; i++) {
      expect(await store.add(trip('$i', 'S$i', 'T$i')), isTrue);
    }
    expect(await store.add(trip('11', 'Y', 'Z')), isFalse);
    expect((await store.read()).length, maxSavedTrips);
  });

  test('a corrupt or unknown entry is skipped, the rest kept', () async {
    await SharedPreferencesAsync().setString('saved_trips.v1', jsonEncode([
      {'id': '1', 'name': 'ok', 'from': {'kind': 'stop', 'stopId': 'A', 'name': 'A'}, 'to': {'kind': 'stop', 'stopId': 'B', 'name': 'B'}},
      {'id': '2', 'name': 'bad', 'from': {'kind': 'nope'}, 'to': {'kind': 'stop', 'stopId': 'B', 'name': 'B'}},
      {'id': '3', 'name': 'no ends'},
      'garbage',
    ]));
    expect((await SavedTripStore().read()).map((t) => t.id), ['1']);
  });

  test('unreadable JSON reads as no trips, and saving still works after', () async {
    await SharedPreferencesAsync().setString('saved_trips.v1', '{not json');
    final store = SavedTripStore();
    expect(await store.read(), isEmpty);
    expect(await store.add(trip('1', 'A', 'B')), isTrue);
    expect((await store.read()).single.id, '1');
  });
}

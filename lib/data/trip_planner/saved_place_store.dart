import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/trip_planner/place.dart';

const maxSavedPlaces = 12;
const maxRecentPlaces = 10;

enum SavedPlaceIcon { home, work, school, star }

/// A place the rider named: Home, Work, a school or a favourite (spec 2026-10-12 §3.5).
class SavedPlace {
  const SavedPlace({required this.id, required this.name, required this.icon, required this.place});
  final String id;
  final String name;
  final SavedPlaceIcon icon;
  final Place place;

  SavedPlace withIcon(SavedPlaceIcon i) => SavedPlace(id: id, name: name, icon: i, place: place);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'icon': icon.name, 'place': place.toJson()};

  /// Null for a malformed entry; an unknown icon reads as a star.
  static SavedPlace? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['name'] is! String) return null;
    final place = Place.fromJson(json['place']);
    if (place == null) return null;
    final icon = SavedPlaceIcon.values.where((i) => i.name == json['icon']).firstOrNull ?? SavedPlaceIcon.star;
    return SavedPlace(id: json['id'] as String, name: json['name'] as String, icon: icon, place: place);
  }
}

List<Object?> _list(String? raw) {
  if (raw == null) return const [];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : const [];
  } on FormatException {
    return const [];
  }
}

/// Saved places, on the phone only.
class SavedPlaceStore {
  SavedPlaceStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;
  static const _key = 'saved_places.v1';

  Future<List<SavedPlace>> read() async => [for (final e in _list(await _prefs.getString(_key))) ?SavedPlace.fromJson(e)];

  Future<void> _write(List<SavedPlace> all) => _prefs.setString(_key, jsonEncode([for (final p in all) p.toJson()]));

  /// Adds or replaces [p] by id. Home and Work are unique: an older one becomes a star.
  Future<bool> put(SavedPlace p) async {
    final all = await read();
    final exists = all.any((e) => e.id == p.id);
    if (!exists && all.length >= maxSavedPlaces) return false;
    final unique = p.icon == SavedPlaceIcon.home || p.icon == SavedPlaceIcon.work;
    final next = [
      for (final e in all)
        if (e.id == p.id) p else if (unique && e.icon == p.icon) e.withIcon(SavedPlaceIcon.star) else e,
      if (!exists) p,
    ];
    await _write(next);
    return true;
  }

  Future<void> remove(String id) async => _write([for (final e in await read()) if (e.id != id) e]);
}

/// The last destinations, newest first.
class RecentPlaceStore {
  RecentPlaceStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;
  static const _key = 'recent_places.v1';

  Future<List<Place>> read() async => [for (final e in _list(await _prefs.getString(_key))) ?Place.fromJson(e)];

  Future<void> push(Place p) async {
    final next = [p, for (final e in await read()) if (e != p) e].take(maxRecentPlaces);
    await _prefs.setString(_key, jsonEncode([for (final e in next) e.toJson()]));
  }
}

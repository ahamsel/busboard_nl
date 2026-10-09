import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/trip_planner/place.dart';

const maxSavedTrips = 10;

/// A trip the rider saved: its ends and a name, nothing else (spec §3.5).
class SavedTrip {
  const SavedTrip({required this.id, required this.name, required this.from, required this.to});
  final String id;
  final String name;
  final Place from;
  final Place to;

  SavedTrip renamed(String name) => SavedTrip(id: id, name: name, from: from, to: to);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'from': from.toJson(), 'to': to.toJson()};

  /// Null for a malformed entry (corrupt or from an unknown format).
  static SavedTrip? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['name'] is! String) return null;
    final from = Place.fromJson(json['from']);
    final to = Place.fromJson(json['to']);
    if (from == null || to == null) return null;
    return SavedTrip(id: json['id'] as String, name: json['name'] as String, from: from, to: to);
  }
}

/// Saved trips, on the phone only ([SharedPreferencesAsync], like the alert store).
class SavedTripStore {
  SavedTripStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  static const _key = 'saved_trips.v1';

  Future<List<SavedTrip>> read() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final e in list) ?SavedTrip.fromJson(e)];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _write(List<SavedTrip> trips) =>
      _prefs.setString(_key, jsonEncode([for (final t in trips) t.toJson()]));

  /// False when the list is full, or a trip with the same ends is already saved.
  Future<bool> add(SavedTrip trip) async {
    final trips = await read();
    if (trips.length >= maxSavedTrips) return false;
    if (trips.any((t) => t.from == trip.from && t.to == trip.to)) return false;
    await _write([...trips, trip]);
    return true;
  }

  Future<void> rename(String id, String name) async =>
      _write([for (final t in await read()) t.id == id ? t.renamed(name) : t]);

  Future<void> remove(String id) async => _write([for (final t in await read()) if (t.id != id) t]);
}

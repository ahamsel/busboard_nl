import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many recently viewed stops are kept. The Board shows at most three of them, after your stop and your saved
/// stops, so a few more are kept than it shows.
const maxRecentStops = 8;

/// The stops viewed lately, on the Board or in a stop's card (spec 2026-10-15 §3): stop ids, newest first, each once.
/// Kept on the phone only.
class RecentStopStore {
  RecentStopStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;

  static const key = 'recent_stops.v1';

  /// Newest first; an unreadable or malformed entry reads as none.
  Future<List<String>> read() async {
    final raw = await _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return {for (final id in decoded) if (id is String && id.isNotEmpty) id}.take(maxRecentStops).toList();
    } on FormatException {
      return const [];
    }
  }

  /// [stopId] becomes the newest; an older visit to it is dropped.
  Future<void> push(String stopId) async {
    final next = [stopId, for (final id in await read()) if (id != stopId) id].take(maxRecentStops).toList();
    await _prefs.setString(key, jsonEncode(next));
  }
}

final recentStopStoreProvider = Provider<RecentStopStore>((ref) => RecentStopStore());

/// The recently viewed stops, newest first.
class RecentStopsNotifier extends AsyncNotifier<List<String>> {
  Future<void> _queue = Future.value();

  @override
  Future<List<String>> build() => ref.read(recentStopStoreProvider).read();

  /// Records a view of [stopId]. One at a time (the store reads, changes and writes the whole list), and it never
  /// throws: a view that can't be stored (a full disk) is only a recent lost.
  Future<void> push(String stopId) => _queue = _queue.then((_) async {
        try {
          final store = ref.read(recentStopStoreProvider);
          await store.push(stopId);
          final next = await store.read();
          if (ref.mounted) state = AsyncData(next);
        } catch (_) {
          // Not stored.
        }
      });
}

final recentStopsProvider = AsyncNotifierProvider<RecentStopsNotifier, List<String>>(RecentStopsNotifier.new);

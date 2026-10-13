import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The stop whose Board (its sheet at full height) was open when the app last went to the background, so a cold
/// start reopens it the way the rider left it. Only the stop id, kept on the phone.
class BoardOpenStore {
  const BoardOpenStore();

  static const key = 'board_open.v1';

  Future<String?> read() => SharedPreferencesAsync().getString(key);
  Future<void> save(String stopId) => SharedPreferencesAsync().setString(key, stopId);
  Future<void> clear() => SharedPreferencesAsync().remove(key);
}

final boardOpenStoreProvider = Provider<BoardOpenStore>((ref) => const BoardOpenStore());

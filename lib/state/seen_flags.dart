import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The SharedPreferences key of the bar's one-time lift (spec 2026-10-14 §3.6).
const barHintSeenKey = 'home_bar_hint_seen.v1';

/// A one-time hint that, once seen, never shows again: a flag kept on the phone under [key].
class SeenFlagNotifier extends AsyncNotifier<bool> {
  SeenFlagNotifier(this.key);

  /// Already seen, for tests.
  factory SeenFlagNotifier.seen(String key) = _AlreadySeen;

  final String key;

  @override
  Future<bool> build() async => await SharedPreferencesAsync().getBool(key) ?? false;

  /// Stores the flag. Waits for the stored value first, so a read still in flight can't bring the hint back.
  Future<void> markSeen() async {
    try {
      if (await future) return;
    } catch (_) {
      // Unreadable: store it anyway.
    }
    state = const AsyncData(true);
    await SharedPreferencesAsync().setBool(key, true);
  }
}

class _AlreadySeen extends SeenFlagNotifier {
  _AlreadySeen(super.key);

  @override
  Future<bool> build() async => true;
}

/// Whether the bar's one-time lift has played.
final barHintSeenProvider = AsyncNotifierProvider<SeenFlagNotifier, bool>(() => SeenFlagNotifier(barHintSeenKey));

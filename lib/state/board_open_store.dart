import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The stop whose Board (its sheet at full height) was open when the app last went to the background, so a cold
/// start reopens it the way the rider left it. Only the stop id, kept on the phone.
///
/// It is written only as the app goes to the background: an app killed while on screen (a crash, or a kill from
/// the debugger) loses a Board opened since, and the next start opens home.
class BoardOpenStore {
  const BoardOpenStore();

  static const key = 'board_open.v1';

  Future<String?> read() => SharedPreferencesAsync().getString(key);
  Future<void> save(String stopId) => SharedPreferencesAsync().setString(key, stopId);
  Future<void> clear() => SharedPreferencesAsync().remove(key);
}

final boardOpenStoreProvider = Provider<BoardOpenStore>((ref) => const BoardOpenStore());

/// Completes once the app has checked whether a notification launched it: true when it opened that notification's
/// Board link. The Board left open is reopened only after, so a launch link wins without the old Board flashing first.
final launchLinkCheckedProvider = Provider<Completer<bool>>((ref) => Completer<bool>());

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_sheet_provider.dart';

/// The home's two tabs (spec 2026-10-15 §2).
enum HomeTab { board, map }

/// Where a cold start opens: [tab], and on an upgrade from a Board left open in 1.4, that Board's stop.
@immutable
class HomeTabStart {
  const HomeTabStart(this.tab, {this.boardStopId});
  final HomeTab tab;
  final String? boardStopId;
}

/// The tab used last (spec §2.2), kept on the phone as `board` or `map`.
class HomeTabStore {
  const HomeTabStore();

  static const key = 'home_tab.v1';

  /// 1.4's "Board left open" (a stop id). Read once on upgrade, then cleared.
  static const legacyBoardOpenKey = 'board_open.v1';

  /// The tab used last; the Board on a first launch. An upgrade from 1.4 with a Board left open opens the Board on
  /// that stop: the old key is cleared and the Board is stored as the tab.
  Future<HomeTabStart> readStart() async {
    final prefs = SharedPreferencesAsync();
    final legacy = await prefs.getString(legacyBoardOpenKey);
    if (legacy != null) {
      await prefs.remove(legacyBoardOpenKey);
      if (legacy.isNotEmpty) {
        await prefs.setString(key, HomeTab.board.name);
        return HomeTabStart(HomeTab.board, boardStopId: legacy);
      }
    }
    final stored = await prefs.getString(key);
    return HomeTabStart(stored == HomeTab.map.name ? HomeTab.map : HomeTab.board);
  }

  Future<void> save(HomeTab tab) => SharedPreferencesAsync().setString(key, tab.name);
}

final homeTabStoreProvider = Provider<HomeTabStore>((ref) => const HomeTabStore());

/// The tab showing: null for the moment the stored one is being read at launch.
class HomeTabNotifier extends Notifier<HomeTab?> {
  HomeTabNotifier();

  /// Starts on [tab] without reading the phone (tests).
  factory HomeTabNotifier.fixed(HomeTab tab) = _FixedHomeTab;

  /// A tab was chosen (a tap, a link, a follow) while the stored one was still being read: the choice wins.
  bool _chosen = false;

  @override
  HomeTab? build() {
    _chosen = false;
    unawaited(_readStart());
    return null;
  }

  Future<void> _readStart() async {
    var start = const HomeTabStart(HomeTab.board);
    try {
      start = await ref.read(homeTabStoreProvider).readStart();
    } catch (_) {
      // Unreadable: a first launch.
    }
    if (!ref.mounted) return;
    final stop = start.boardStopId;
    if (stop != null) ref.read(boardStopProvider.notifier).restore(stop);
    if (!_chosen) state = start.tab;
  }

  /// Shows [tab] and stores it as the one to open on next time.
  void select(HomeTab tab) {
    _chosen = true;
    if (state == tab) return;
    state = tab;
    unawaited(ref.read(homeTabStoreProvider).save(tab).catchError((Object _) {}));
  }

  /// The Board tab, showing [stopId] (the stop line, Open board, a notification, a `/board/` link).
  void showBoard(String stopId) {
    ref.read(boardStopProvider.notifier).select(stopId);
    select(HomeTab.board);
  }

  /// [stopId]'s departures where the rider is: on the Board, the Board shows it; anywhere else, its card on the map.
  void openStop(String stopId) {
    if (state == HomeTab.board) return showBoard(stopId);
    ref.read(homeSheetProvider.notifier).open(StopSheet(stopId));
    select(HomeTab.map);
  }
}

class _FixedHomeTab extends HomeTabNotifier {
  _FixedHomeTab(this._tab);
  final HomeTab _tab;

  @override
  HomeTab? build() => _tab;
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, HomeTab?>(HomeTabNotifier.new);

/// The stop the Board shows, as last picked. [nearMe]: picked by Near me (its chip is the selected one).
@immutable
class BoardStop {
  const BoardStop(this.stopId, {this.nearMe = false});
  final String stopId;
  final bool nearMe;

  @override
  bool operator ==(Object other) => other is BoardStop && other.stopId == stopId && other.nearMe == nearMe;
  @override
  int get hashCode => Object.hash(stopId, nearMe);
  @override
  String toString() => 'BoardStop($stopId${nearMe ? ', near me' : ''})';
}

/// The Board's picked stop, or null while none is (the Board then shows your stop). Kept for the session only.
class BoardStopNotifier extends Notifier<BoardStop?> {
  @override
  BoardStop? build() => null;

  /// The Board shows [stopId].
  void select(String stopId, {bool nearMe = false}) {
    state = BoardStop(stopId, nearMe: nearMe);
  }

  /// A Board left open in 1.4, unless something was picked first (a launch link wins).
  void restore(String stopId) => state ??= BoardStop(stopId);
}

final boardStopProvider = NotifierProvider<BoardStopNotifier, BoardStop?>(BoardStopNotifier.new);

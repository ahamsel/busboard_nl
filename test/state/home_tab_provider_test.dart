import 'dart:async';

import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../trip_planner/test_network.dart';

/// The schedule these tests run on: stops A..H, X, Y, Z.
final _net = TestNetwork();

List<Override> _schedule([Future<void>? gate]) => [
      gtfsRepositoryProvider.overrideWith((ref) async {
        if (gate != null) await gate;
        return _net.repo;
      }),
    ];

/// A fresh app start over what the phone holds ([prefs]).
ProviderContainer _start([Map<String, Object> prefs = const {}, List<Override>? schedule]) {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(prefs);
  final c = ProviderContainer(overrides: schedule ?? _schedule());
  addTearDown(c.dispose);
  return c;
}

/// The same phone, started again.
ProviderContainer _restart() {
  final c = ProviderContainer(overrides: _schedule());
  addTearDown(c.dispose);
  return c;
}

Future<HomeTab?> _tabOnceRead(ProviderContainer c) async {
  c.read(homeTabProvider);
  await pumpEventQueue();
  return c.read(homeTabProvider);
}

void main() {
  test('a first launch opens on the Board (spec 2026-10-15 §2.2)', () async {
    final c = _start();
    expect(c.read(homeTabProvider), isNull, reason: 'nothing is shown until the stored tab is read');
    expect(await _tabOnceRead(c), HomeTab.board);
  });

  test('the tab used last is stored, and the next start opens on it', () async {
    final c = _start();
    await _tabOnceRead(c);
    c.read(homeTabProvider.notifier).select(HomeTab.map);
    expect(c.read(homeTabProvider), HomeTab.map);
    await pumpEventQueue();
    expect(await SharedPreferencesAsync().getString(HomeTabStore.key), 'map');
    expect(await _tabOnceRead(_restart()), HomeTab.map);
  });

  test('an upgrade with a Board left open in 1.4 opens the Board on that stop, and the old key goes', () async {
    final c = _start({HomeTabStore.legacyBoardOpenKey: 'C'});
    expect(await _tabOnceRead(c), HomeTab.board);
    expect(c.read(boardStopProvider), const BoardStop('C'));
    expect(await SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey), isNull);
    expect(await SharedPreferencesAsync().getString(HomeTabStore.key), 'board');
    final next = _restart();
    expect(await _tabOnceRead(next), HomeTab.board);
    expect(next.read(boardStopProvider), isNull, reason: 'the migration runs once');
  });

  test('a Board left open in 1.4 on a stop the schedule no longer has is not restored', () async {
    final c = _start({HomeTabStore.legacyBoardOpenKey: 'GONE'});
    expect(await _tabOnceRead(c), HomeTab.board, reason: 'the Board still opens, on your stop or Choose your stop');
    await pumpEventQueue();
    expect(c.read(boardStopProvider), isNull);
    expect(await SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey), isNull);
  });

  test('the tab shows at once while the schedule loads, and the 1.4 stop is checked when it has', () async {
    final gate = Completer<void>();
    final c = _start({HomeTabStore.legacyBoardOpenKey: 'GONE'}, _schedule(gate.future));
    expect(await _tabOnceRead(c), HomeTab.board, reason: 'not held back by the schedule');
    expect(c.read(boardStopProvider), isNull);
    gate.complete();
    await pumpEventQueue();
    expect(c.read(boardStopProvider), isNull, reason: 'GONE is not in it');

    final gate2 = Completer<void>();
    final c2 = _start({HomeTabStore.legacyBoardOpenKey: 'C'}, _schedule(gate2.future));
    expect(await _tabOnceRead(c2), HomeTab.board);
    expect(c2.read(boardStopProvider), isNull, reason: 'not before there is a schedule to check it against');
    gate2.complete();
    await pumpEventQueue();
    expect(c2.read(boardStopProvider), const BoardStop('C'));
  });

  test('a schedule that fails to load says nothing against the 1.4 stop', () async {
    final c = _start({HomeTabStore.legacyBoardOpenKey: 'C'}, [
      gtfsRepositoryProvider.overrideWith((ref) async => throw StateError('no schedule')),
    ]);
    await _tabOnceRead(c);
    await pumpEventQueue();
    expect(c.read(boardStopProvider), const BoardStop('C'));
  });

  test('the migration stores the Board before it clears the 1.4 key, so a failed write keeps the stop', () async {
    final log = <String>[];
    SharedPreferencesAsyncPlatform.instance = _LoggingPrefs({HomeTabStore.legacyBoardOpenKey: 'C'}, log);
    await const HomeTabStore().readStart();
    expect(log, ['set home_tab.v1', 'remove board_open.v1']);

    // A write that fails leaves the 1.4 key where it was, to be migrated again on the next start; the stop shows now.
    SharedPreferencesAsyncPlatform.instance =
        _LoggingPrefs({HomeTabStore.legacyBoardOpenKey: 'C'}, log, failSet: true);
    final start = await const HomeTabStore().readStart();
    expect(start.boardStopId, 'C');
    expect(await SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey), 'C');
  });

  test('an empty 1.4 key is cleared and opens as a first launch would', () async {
    final c = _start({HomeTabStore.legacyBoardOpenKey: '', HomeTabStore.key: 'map'});
    expect(await _tabOnceRead(c), HomeTab.map);
    expect(c.read(boardStopProvider), isNull);
    expect(await SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey), isNull);
  });

  test('a link that lands before the stored tab is read wins over it, and over the 1.4 Board', () async {
    final c = _start({HomeTabStore.key: 'map', HomeTabStore.legacyBoardOpenKey: 'C'});
    c.read(homeTabProvider);
    c.read(homeTabProvider.notifier).showBoard('A');
    await pumpEventQueue();
    expect(c.read(homeTabProvider), HomeTab.board);
    expect(c.read(boardStopProvider), const BoardStop('A'));
    expect(await SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey), isNull);
  });

  test('a tab chosen before the stored one is read stays chosen', () async {
    final c = _start({HomeTabStore.key: 'board'});
    c.read(homeTabProvider);
    c.read(homeTabProvider.notifier).select(HomeTab.map);
    await pumpEventQueue();
    expect(c.read(homeTabProvider), HomeTab.map);
  });

  test('openStop shows the stop on the Board when the Board is showing, else opens its card on the map', () async {
    final c = _start({HomeTabStore.key: 'board'});
    await _tabOnceRead(c);
    await c.read(gtfsRepositoryProvider.future);
    c.read(homeTabProvider.notifier).openStop('B');
    expect(c.read(boardStopProvider), const BoardStop('B'));
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    c.read(homeTabProvider.notifier).select(HomeTab.map);
    c.read(homeTabProvider.notifier).openStop('C');
    expect(c.read(homeSheetProvider), const StopSheet('C'));
    expect(c.read(boardStopProvider), const BoardStop('B'), reason: 'the Board keeps its own stop');
  });

  test('showBoard with a stop the schedule does not know leaves the Board as it was (fix round 1)', () async {
    final c = _start({HomeTabStore.key: 'map'});
    await _tabOnceRead(c);
    await c.read(gtfsRepositoryProvider.future);
    c.read(homeTabProvider.notifier).showBoard('9999');
    expect(c.read(homeTabProvider), HomeTab.board, reason: 'the Board still opens');
    expect(c.read(boardStopProvider), isNull, reason: 'on its default stop, not an empty "Stop 9999"');
    c.read(homeTabProvider.notifier).showBoard('B');
    expect(c.read(boardStopProvider), const BoardStop('B'));
    c.read(homeTabProvider.notifier).showBoard('9999');
    expect(c.read(boardStopProvider), const BoardStop('B'), reason: 'an unknown stop never replaces a shown one');
  });

  test('showBoard before the schedule loads waits for it, then ignores an unknown stop', () async {
    final gate = Completer<void>();
    final c = _start({HomeTabStore.key: 'map'}, _schedule(gate.future));
    c.read(homeTabProvider);
    c.read(homeTabProvider.notifier).showBoard('9999');
    c.read(homeTabProvider.notifier).showBoard('B');
    await pumpEventQueue();
    expect(c.read(boardStopProvider), isNull, reason: 'nothing is decided before the schedule is there');
    gate.complete();
    await pumpEventQueue();
    expect(c.read(boardStopProvider), const BoardStop('B'));
  });

  test('a fixed tab (tests) is there at once and reads nothing', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({HomeTabStore.key: 'board'});
    final c = ProviderContainer(overrides: [homeTabProvider.overrideWith(() => HomeTabNotifier.fixed(HomeTab.map))]);
    addTearDown(c.dispose);
    expect(c.read(homeTabProvider), HomeTab.map);
  });

  test("restore never replaces a stop the rider picked", () async {
    final c = _start();
    c.read(boardStopProvider.notifier).select('A', nearMe: true);
    c.read(boardStopProvider.notifier).restore('C');
    await pumpEventQueue();
    expect(c.read(boardStopProvider), const BoardStop('A', nearMe: true));
  });
}

/// Records the writes it passes on, and can fail the sets.
base class _LoggingPrefs extends InMemorySharedPreferencesAsync {
  _LoggingPrefs(super.data, this.log, {this.failSet = false}) : super.withData();
  final List<String> log;
  final bool failSet;

  @override
  Future<bool> setString(String key, String value, SharedPreferencesOptions options) {
    log.add('set $key');
    if (failSet) throw StateError('disk full');
    return super.setString(key, value, options);
  }

  @override
  Future<bool> clear(ClearPreferencesParameters parameters, SharedPreferencesOptions options) {
    // SharedPreferencesAsync.remove clears the one key.
    log.add('remove ${parameters.filter.allowList!.single}');
    return super.clear(parameters, options);
  }
}

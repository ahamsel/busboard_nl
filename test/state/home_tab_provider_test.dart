import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A fresh app start over what the phone holds ([prefs]).
ProviderContainer _start([Map<String, Object> prefs = const {}]) {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(prefs);
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

/// The same phone, started again.
ProviderContainer _restart() {
  final c = ProviderContainer();
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
    c.read(homeTabProvider.notifier).openStop('B');
    expect(c.read(boardStopProvider), const BoardStop('B'));
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    c.read(homeTabProvider.notifier).select(HomeTab.map);
    c.read(homeTabProvider.notifier).openStop('C');
    expect(c.read(homeSheetProvider), const StopSheet('C'));
    expect(c.read(boardStopProvider), const BoardStop('B'), reason: 'the Board keeps its own stop');
  });

  test('a fixed tab (tests) is there at once and reads nothing', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({HomeTabStore.key: 'board'});
    final c = ProviderContainer(overrides: [homeTabProvider.overrideWith(() => HomeTabNotifier.fixed(HomeTab.map))]);
    addTearDown(c.dispose);
    expect(c.read(homeTabProvider), HomeTab.map);
  });

  test("restore never replaces a stop the rider picked", () {
    final c = _start();
    c.read(boardStopProvider.notifier).select('A', nearMe: true);
    c.read(boardStopProvider.notifier).restore('C');
    expect(c.read(boardStopProvider), const BoardStop('A', nearMe: true));
  });
}

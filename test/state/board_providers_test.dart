import 'dart:async';

import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/board_providers.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/recent_stops_provider.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../trip_planner/test_network.dart';

SavedPlace _saved(String id, Place place, {SavedPlaceIcon icon = SavedPlaceIcon.star}) =>
    SavedPlace(id: id, name: id, icon: icon, place: place);

final _home = _saved('Home', StopPlace(stopId: 'H', name: 'Harbour'), icon: SavedPlaceIcon.home);
final _work = _saved('Work', StopPlace(stopId: 'W', name: 'Water St'), icon: SavedPlaceIcon.work);
final _pin = _saved('Gym', PinPlace(lat: 47.5, lon: -52.7, label: 'Gym'));

class _Mine extends SettingsNotifier {
  _Mine(this.stopId);
  final String? stopId;
  @override
  AppSettings build() => AppSettings(selectedStopId: stopId);
}

class _Saved extends SavedPlacesNotifier {
  _Saved(this.places);
  final List<SavedPlace> places;
  @override
  Future<List<SavedPlace>> build() async => places;
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  group('recent stops (recent_stops.v1)', () {
    test('newest first, each stop once', () async {
      final s = RecentStopStore();
      for (final id in ['A', 'B', 'A', 'C']) {
        await s.push(id);
      }
      expect(await s.read(), ['C', 'A', 'B']);
    });

    test('keeps the last $maxRecentStops only', () async {
      final s = RecentStopStore();
      for (var i = 0; i < maxRecentStops + 3; i++) {
        await s.push('$i');
      }
      final read = await s.read();
      expect(read, hasLength(maxRecentStops));
      expect(read.first, '${maxRecentStops + 2}');
    });

    test('a malformed entry reads as none', () async {
      for (final raw in ['not json', '{"a":1}', '[1, "", "A", "A"]']) {
        await SharedPreferencesAsync().setString(RecentStopStore.key, raw);
        expect(await RecentStopStore().read(), raw.startsWith('[') ? ['A'] : isEmpty, reason: raw);
      }
    });

    test('picking a stop on the Board records it, newest first', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(boardStopProvider.notifier).select('A');
      c.read(boardStopProvider.notifier).select('B');
      c.read(boardStopProvider.notifier).select('A');
      await pumpEventQueue();
      expect(c.read(recentStopsProvider).value, ['A', 'B']);
      expect(await RecentStopStore().read(), ['A', 'B']);
    });

    test('a store that fails to write loses only the recent', () async {
      final c = ProviderContainer(overrides: [recentStopStoreProvider.overrideWithValue(_FailingStore())]);
      addTearDown(c.dispose);
      await expectLater(c.read(recentStopsProvider.notifier).push('A'), completes);
    });
  });

  group('the Board chips (spec 2026-10-15 §3)', () {
    test('your stop, then saved stops, then up to 3 recent stops; places that are not stops have none', () {
      expect(
        boardStopChips(yourStopId: 'Y', saved: [_home, _pin, _work], recent: ['R1', 'R2', 'R3', 'R4']),
        [
          const BoardChip(BoardChipKind.yours, 'Y'),
          BoardChip(BoardChipKind.saved, 'H', place: _home),
          BoardChip(BoardChipKind.saved, 'W', place: _work),
          const BoardChip(BoardChipKind.recent, 'R1'),
          const BoardChip(BoardChipKind.recent, 'R2'),
          const BoardChip(BoardChipKind.recent, 'R3'),
        ],
      );
    });

    test('a stop has one chip, the first it earns, and recents skip the ones already there', () {
      final chips = boardStopChips(
        yourStopId: 'H',
        saved: [_home, _work, _saved('Work again', StopPlace(stopId: 'W', name: 'Water St'))],
        recent: ['W', 'H', 'R1', 'R2', 'R3'],
      );
      expect(chips.map((c) => '${c.kind.name}:${c.stopId}'),
          ['yours:H', 'saved:W', 'recent:R1', 'recent:R2', 'recent:R3']);
    });

    test('with nothing chosen, nothing saved and nothing viewed, there are none', () {
      expect(boardStopChips(), isEmpty);
    });
  });

  group('the chips only name stops in the loaded schedule', () {
    // The network has stops A..H, X, Y, Z; the GONE ones are stops a later schedule removed.
    ProviderContainer container({String? mine, List<SavedPlace> saved = const [], Future<void>? repoGate}) {
      final net = TestNetwork();
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async {
          if (repoGate != null) await repoGate;
          return net.repo;
        }),
        settingsProvider.overrideWith(() => _Mine(mine)),
        savedPlacesProvider.overrideWith(() => _Saved(saved)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('a removed stop in the recents, saved places or settings gets no chip, and the rest still fill the row',
        () async {
      for (final id in ['GONE', 'A', 'B', 'C', 'D', 'E']) {
        await RecentStopStore().push(id);
      }
      final gone = _saved('Old', StopPlace(stopId: 'GONE2', name: 'Old'));
      final c = container(mine: 'GONE3', saved: [gone, _home]);
      await c.read(gtfsRepositoryProvider.future);
      await c.read(savedPlacesProvider.future);
      await c.read(recentStopsProvider.future);
      final chips = c.read(boardChipsProvider);
      expect(chips.map((c) => '${c.kind.name}:${c.stopId}'), ['saved:H', 'recent:E', 'recent:D', 'recent:C']);
    });

    test('no chips for stops while the schedule is still loading', () async {
      await RecentStopStore().push('A');
      final gate = Completer<void>();
      final c = container(mine: 'B', repoGate: gate.future);
      await c.read(recentStopsProvider.future);
      expect(c.read(boardChipsProvider), isEmpty);
      gate.complete();
      await c.read(gtfsRepositoryProvider.future);
      expect(c.read(boardChipsProvider).map((c) => c.stopId), ['B', 'A']);
    });
  });

  group('the stop the Board shows', () {
    // The network has stops A..H, X, Y, Z. Your stop and saved stops count only when they are in it.
    final homeD = _saved('Home', StopPlace(stopId: 'D', name: 'Stop D'), icon: SavedPlaceIcon.home);
    final workE = _saved('Work', StopPlace(stopId: 'E', name: 'Stop E'), icon: SavedPlaceIcon.work);
    ProviderContainer container({String? mine, List<SavedPlace> saved = const [], Future<void>? repoGate}) {
      final net = TestNetwork();
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async {
          if (repoGate != null) await repoGate;
          return net.repo;
        }),
        settingsProvider.overrideWith(() => _Mine(mine)),
        savedPlacesProvider.overrideWith(() => _Saved(saved)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> loaded(ProviderContainer c) async {
      await c.read(gtfsRepositoryProvider.future);
      await c.read(savedPlacesProvider.future);
    }

    test('the stop picked, over your stop', () async {
      final c = container(mine: 'Y', saved: [homeD]);
      await loaded(c);
      expect(c.read(boardShownStopProvider), const BoardStop('Y'));
      c.read(boardStopProvider.notifier).select('R', nearMe: true);
      expect(c.read(boardShownStopProvider), const BoardStop('R', nearMe: true));
    });

    test('with no stop chosen, the first saved place that is a stop', () async {
      final c = container(saved: [_pin, workE, homeD]);
      await loaded(c);
      expect(c.read(boardShownStopProvider), const BoardStop('E'));
    });

    test('your stop or a saved stop that the loaded schedule lacks is skipped, as the chips skip it', () async {
      final c = container(mine: 'GONE', saved: [_saved('Old', StopPlace(stopId: 'GONE2', name: 'Old')), workE]);
      await loaded(c);
      expect(c.read(boardShownStopProvider), const BoardStop('E'), reason: 'not "Stop GONE" with an empty board');
      final none = container(mine: 'GONE', saved: [_saved('Old', StopPlace(stopId: 'GONE2', name: 'Old'))]);
      await loaded(none);
      expect(none.read(boardShownStopProvider), isNull);
    });

    test('while the schedule loads there is nothing to check against: your stop shows (no empty-state flash)',
        () async {
      final gate = Completer<void>();
      final c = container(mine: 'GONE', saved: [homeD], repoGate: gate.future);
      await c.read(savedPlacesProvider.future);
      expect(c.read(boardShownStopProvider), const BoardStop('GONE'));
      gate.complete();
      await c.read(gtfsRepositoryProvider.future);
      expect(c.read(boardShownStopProvider), const BoardStop('D'), reason: 'and is skipped once the schedule says no');
    });

    test('a schedule that fails to load says nothing against your stop: the Board shows it, with its error state',
        () async {
      final c = ProviderContainer(overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => throw StateError('no schedule')),
        settingsProvider.overrideWith(() => _Mine('B')),
        savedPlacesProvider.overrideWith(() => _Saved([homeD])),
      ]);
      addTearDown(c.dispose);
      await expectLater(c.read(gtfsRepositoryProvider.future), throwsStateError);
      await c.read(savedPlacesProvider.future);
      expect(c.read(boardShownStopProvider), const BoardStop('B'), reason: 'not "Choose your stop"');
    });

    test('none at all: null, and the Board asks you to choose', () async {
      final c = container(saved: [_pin]);
      await loaded(c);
      expect(c.read(boardShownStopProvider), isNull);
    });

    test('not ready until your stop and your saved places are read', () async {
      final c = container(mine: 'Y');
      expect(c.read(boardReadyProvider), isFalse);
      await c.read(savedPlacesProvider.future);
      await c.read(settingsLoadedProvider.future);
      expect(c.read(boardReadyProvider), isTrue);
    });
  });
}

class _FailingStore extends RecentStopStore {
  @override
  Future<void> push(String stopId) async => throw StateError('disk full');
}

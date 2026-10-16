import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Journey _journey(int departs) => Journey(
      serviceDate: DateTime(2026, 10, 12),
      legs: [WalkLeg(fromStopId: null, toStopId: 'A', seconds: 600, startSeconds: departs)],
    );

void main() {
  late ProviderContainer c;
  HomeSheetNotifier n() => c.read(homeSheetProvider.notifier);
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('starts home with a one-entry stack', () {
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    expect(n().stack, hasLength(1));
    expect(n().back(), isFalse);
  });

  test('a stop then another stop replaces, back goes home', () {
    n().open(const StopSheet('1150'));
    n().open(const StopSheet('1600'));
    expect((c.read(homeSheetProvider) as StopSheet).stopId, '1600');
    expect(n().stack, hasLength(2));
    expect(n().back(), isTrue);
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
  });

  test('a bus replaces a stop on top', () {
    n().open(const StopSheet('1150'));
    n().open(const BusSheet('1524'));
    expect(n().stack.map((s) => s.runtimeType), [HomeSheetHome, BusSheet]);
  });

  test('journey → options → home on back (Review Focus 2)', () {
    n().open(const OptionsSheet());
    n().open(JourneySheet(_journey(1000)));
    expect(n().back(), isTrue);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(n().back(), isTrue);
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    expect(n().back(), isFalse);
  });

  test('a stop opened over options stacks, and back returns to the options', () {
    n().open(const OptionsSheet());
    n().open(const StopSheet('1150'));
    expect(n().back(), isTrue);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
  });

  test('opening options again drops a journey above the old options', () {
    n().open(const OptionsSheet());
    n().open(JourneySheet(_journey(1000)));
    n().open(const OptionsSheet());
    expect(n().stack.map((s) => s.runtimeType), [HomeSheetHome, OptionsSheet]);
  });

  test('a second journey replaces the first', () {
    n().open(const OptionsSheet());
    n().open(JourneySheet(_journey(1000)));
    n().open(JourneySheet(_journey(2000)));
    expect(n().stack, hasLength(3));
    expect((c.read(homeSheetProvider) as JourneySheet).journey.departs, 2000);
  });

  test('home() clears everything; opening the top again is a no-op', () {
    n().open(const StopSheet('1150'));
    n().open(const StopSheet('1150'));
    expect(n().stack, hasLength(2));
    n().home();
    expect(n().stack, hasLength(1));
  });

  test('every sheet has its own id, so the sheet at full is never mistaken for another', () {
    final j1 = Journey(serviceDate: DateTime(2026, 10, 7), legs: const []);
    final j2 = Journey(serviceDate: DateTime(2026, 10, 7), legs: const []);
    final ids = [
      sheetIdOf(const HomeSheetHome()),
      sheetIdOf(const StopSheet('1150')),
      sheetIdOf(const StopSheet('1151')),
      sheetIdOf(const BusSheet('1150')),
      sheetIdOf(const OptionsSheet()),
      sheetIdOf(JourneySheet(j1)),
      sheetIdOf(JourneySheet(j2)),
      sheetIdOf('follow:2573'),
    ];
    expect(ids.toSet(), hasLength(ids.length));
    expect(sheetIdOf(const StopSheet('1150')), sheetIdOf(const StopSheet('1150')));
  });
}

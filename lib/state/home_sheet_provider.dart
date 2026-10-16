import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/trip_planner/journey.dart';
import 'map_request_provider.dart';

/// What the home screen's sheet shows (spec 2026-10-12 §3). The follow card is not a state: it shows over
/// [HomeSheetHome] while a bus is followed.
sealed class HomeSheet {
  const HomeSheet();
}

final class HomeSheetHome extends HomeSheet {
  const HomeSheetHome();
  @override
  bool operator ==(Object other) => other is HomeSheetHome;
  @override
  int get hashCode => (HomeSheetHome).hashCode;
}

/// A stop's card on the map: its departures, with Open board for the Board tab.
final class StopSheet extends HomeSheet {
  const StopSheet(this.stopId);
  final String stopId;
  @override
  bool operator ==(Object other) => other is StopSheet && other.stopId == stopId;
  @override
  int get hashCode => Object.hash(StopSheet, stopId);
}

/// A bus tapped on the map.
final class BusSheet extends HomeSheet {
  const BusSheet(this.vehicleId);
  final String vehicleId;
  @override
  bool operator ==(Object other) => other is BusSheet && other.vehicleId == vehicleId;
  @override
  int get hashCode => Object.hash(BusSheet, vehicleId);
}

/// Trip options for [planQueryProvider]'s draft.
final class OptionsSheet extends HomeSheet {
  const OptionsSheet();
  @override
  bool operator ==(Object other) => other is OptionsSheet;
  @override
  int get hashCode => (OptionsSheet).hashCode;
}

/// One journey's steps.
final class JourneySheet extends HomeSheet {
  const JourneySheet(this.journey);
  final Journey journey;
  @override
  bool operator ==(Object other) => other is JourneySheet && identical(other.journey, journey);
  @override
  int get hashCode => identityHashCode(journey);
}

/// The sheet's back stack. Back walks it down; from home the system leaves the app.
class HomeSheetNotifier extends Notifier<HomeSheet> {
  final _stack = <HomeSheet>[const HomeSheetHome()];

  /// Oldest first; always starts with [HomeSheetHome].
  List<HomeSheet> get stack => List.unmodifiable(_stack);

  @override
  HomeSheet build() {
    _stack
      ..clear()
      ..add(const HomeSheetHome());
    return const HomeSheetHome();
  }

  /// Opens [sheet] over the stack. The card already on top, opened again (a second notification tap), stays as it
  /// is in the stack, and [homeSheetReopenedProvider] tells the home screen to bring it back to half.
  void open(HomeSheet sheet) {
    if (sheet is HomeSheetHome) return home();
    // A trip's options or steps are only on the map (spec 2026-10-15 §2.3), opened again or not.
    if (sheet is OptionsSheet || sheet is JourneySheet) ref.read(mapRequestProvider.notifier).request();
    if (_stack.last == sheet) {
      ref.read(homeSheetReopenedProvider.notifier)._bump();
      return;
    }
    final top = _stack.last;
    switch (sheet) {
      case StopSheet() || BusSheet() when top is StopSheet || top is BusSheet:
        _stack[_stack.length - 1] = sheet;
      case OptionsSheet():
        final first = _stack.indexWhere((s) => s is OptionsSheet);
        if (first != -1) _stack.removeRange(first, _stack.length);
        _stack.add(sheet);
      case JourneySheet() when top is JourneySheet:
        _stack[_stack.length - 1] = sheet;
      default:
        _stack.add(sheet);
    }
    state = _stack.last;
  }

  /// False when already home (the caller lets the system leave the app).
  bool back() {
    if (_stack.length <= 1) return false;
    _stack.removeLast();
    state = _stack.last;
    return true;
  }

  void home() {
    _stack
      ..clear()
      ..add(const HomeSheetHome());
    state = const HomeSheetHome();
  }
}

final homeSheetProvider = NotifierProvider<HomeSheetNotifier, HomeSheet>(HomeSheetNotifier.new);

/// Counts the times the card on top was opened again; the home screen brings that card back to half on each.
final homeSheetReopenedProvider = NotifierProvider<HomeSheetReopenedNotifier, int>(HomeSheetReopenedNotifier.new);

class HomeSheetReopenedNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void _bump() => state++;
}

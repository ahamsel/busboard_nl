import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/trip_planner/journey.dart';

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

/// A stop's sheet: its Board.
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

  /// "Open board": [stopId]'s sheet, pulled up to full height (its Board); on the tablet panel, scrolled to its
  /// departures. A sheet already showing the stop stays as it is in the stack.
  void openBoard(String stopId) {
    final sheet = StopSheet(stopId);
    if (_stack.last != sheet) open(sheet);
    ref.read(boardRequestProvider.notifier)._request(stopId);
  }

  /// "Show map", from a Board at full height: the card on top back to half, its stop centred on the map.
  void showMap() => ref.read(homeSheetReopenedProvider.notifier)._bump();

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

/// A request to show [stopId]'s Board: its sheet at full height. A new object every time, so asking twice is two
/// requests.
final class BoardRequest {
  BoardRequest(this.stopId);
  final String stopId;
}

/// The latest "Open board" (or a cold start reopening the Board left open); the home screen moves the sheet.
final boardRequestProvider = NotifierProvider<BoardRequestNotifier, BoardRequest?>(BoardRequestNotifier.new);

class BoardRequestNotifier extends Notifier<BoardRequest?> {
  @override
  BoardRequest? build() => null;

  void _request(String stopId) => state = BoardRequest(stopId);
}

/// Which sheet the phone's pull-up sheet is showing at its full height, by [sheetIdOf], or null when none is: a stop's
/// sheet there is its Board, and its header button turns from "Open board" into "Show map". A sheet compares the id
/// with its own, so a value left by the sheet it replaced never matches. Always null on the tablet panel, which has no
/// detents.
final sheetAtFullProvider = NotifierProvider<SheetAtFullNotifier, String?>(SheetAtFullNotifier.new);

class SheetAtFullNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// [sheetId] is at full height; null when no sheet is.
  void set(String? sheetId) {
    if (state != sheetId) state = sheetId;
  }
}

/// The id [sheetAtFullProvider] holds for the pull-up sheet showing [sheetKey]: a [HomeSheet], or the follow card's
/// own key (`follow:2573`).
String sheetIdOf(Object sheetKey) => switch (sheetKey) {
      HomeSheetHome() => 'home',
      StopSheet(:final stopId) => 'stop:$stopId',
      BusSheet(:final vehicleId) => 'bus:$vehicleId',
      OptionsSheet() => 'options',
      JourneySheet(:final journey) => 'journey:${identityHashCode(journey)}',
      _ => '$sheetKey',
    };

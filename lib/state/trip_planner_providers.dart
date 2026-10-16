import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gtfs/gtfs_repository.dart';
import '../data/realtime/timetrack_api.dart';
import '../data/trip_planner/saved_trip_store.dart';
import '../domain/trip_planner/journey.dart';
import '../domain/trip_planner/place.dart';
import '../domain/trip_planner/ranking.dart';
import '../domain/trip_planner/timetable_index.dart';
import '../domain/trip_planner/trip_planner.dart';
import 'providers.dart';

final plannerClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

typedef IndexBuilder = Future<TimetableIndex> Function(GtfsRepository repo, DateTime day);

/// Builds a day's index in a background isolate (spec §3.3), sending it only what the index reads (no shapes).
Future<TimetableIndex> buildIndexInBackground(GtfsRepository repo, DateTime day) {
  final slim = GtfsRepository();
  slim.stopsById.addAll(repo.stopsById);
  slim.tripsById.addAll(repo.tripsById);
  slim.stopTimesByStopId.addAll(repo.stopTimesByStopId);
  slim.transfersByFromStop.addAll(repo.transfersByFromStop);
  slim.calendarsById.addAll(repo.calendarsById);
  slim.calendarDates.addAll(repo.calendarDates);
  return Isolate.run(() => TimetableIndex.build(slim, day));
}

final timetableIndexBuilderProvider = Provider<IndexBuilder>((ref) => buildIndexInBackground);

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// The planner for one service day ([day] is date-only), kept for 10 minutes after it was built.
///
/// An error if the schedule's first load fails. A schedule loaded once is used from then on, even when a reload fails
/// (Refresh schedule, offline); a reload that succeeds is waited for, so the planner moves to the new schedule.
final tripPlannerProvider = FutureProvider.autoDispose.family<TripPlanner, DateTime>((ref, day) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);
  // Only the future is watched (a reload starts a new one): watching the state too would build a second planner as
  // the load lands. The schedule loaded before is kept for a reload that fails; it can't stand in while the reload
  // runs, as the stop departures' does, since nothing would move this planner on to the new schedule afterwards.
  final load = ref.watch(gtfsRepositoryProvider.future);
  final kept = ref.read(gtfsRepositoryProvider).value;
  GtfsRepository repo;
  try {
    repo = await load;
  } catch (_) {
    if (kept == null) rethrow;
    repo = kept;
  }
  return TripPlanner(repo, await ref.read(timetableIndexBuilderProvider)(repo, day));
});

/// What the Plan form holds.
class PlanDraft {
  const PlanDraft({this.from, this.to, this.mode = PlanMode.leaveNow, this.time});
  final Place? from;
  final Place? to;
  final PlanMode mode;

  /// The time the rider picked; null until they pick one.
  final DateTime? time;

  /// Leave by or Arrive by with no time picked: the plan is for [planDefaultTimeProvider], which moves with the clock.
  bool get usesDefaultTime => mode != PlanMode.leaveNow && time == null;

  /// [defaultTime] stands in for a time not picked; without it, [defaultPlanTime] of [now].
  PlanQuery? toQuery(DateTime now, {DateTime? defaultTime}) => from == null || to == null
      ? null
      : PlanQuery(
          from: from!,
          to: to!,
          mode: mode,
          time: mode == PlanMode.leaveNow ? now : time ?? defaultTime ?? defaultPlanTime(now),
        );
}

/// Half an hour from [now], rounded up to the next 5 minutes (a time on the mark stays).
DateTime defaultPlanTime(DateTime now) {
  final t = now.add(const Duration(minutes: 30));
  final mark = DateTime(t.year, t.month, t.day, t.hour, t.minute - t.minute % 5);
  return mark == t ? mark : mark.add(const Duration(minutes: 5));
}

/// [defaultPlanTime] for now, moved on as the clock passes each 5-minute mark, so a Leave by or Arrive by time the
/// rider never picked doesn't go stale while the planner stays open.
final planDefaultTimeProvider = Provider.autoDispose<DateTime>((ref) {
  final now = ref.read(plannerClockProvider)();
  final at = defaultPlanTime(now);
  // It moves on once now + 30 min passes [at]; a second's slack so it has.
  final timer = Timer(at.subtract(const Duration(minutes: 30)).difference(now) + const Duration(seconds: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return at;
});

class PlanQueryNotifier extends Notifier<PlanDraft> {
  @override
  PlanDraft build() => const PlanDraft();

  void setFrom(Place? p) => state = PlanDraft(from: p, to: state.to, mode: state.mode, time: state.time);
  void setTo(Place? p) => state = PlanDraft(from: state.from, to: p, mode: state.mode, time: state.time);
  void swap() => state = PlanDraft(from: state.to, to: state.from, mode: state.mode, time: state.time);
  /// Leave by and Arrive by with no time picked plan for [planDefaultTimeProvider], not now: Arrive by now has no bus.
  void setMode(PlanMode m) => state = PlanDraft(from: state.from, to: state.to, mode: m, time: state.time);
  void setTime(DateTime t) => state = PlanDraft(from: state.from, to: state.to, mode: state.mode, time: t);

  /// A saved trip opened from its card: its ends, leaving now.
  void setTrip(Place from, Place to) => state = PlanDraft(from: from, to: to);
}

final planQueryProvider = NotifierProvider<PlanQueryNotifier, PlanDraft>(PlanQueryNotifier.new);

/// The trip whose steps the rider opened and has not closed with back. "Show on map", "Follow bus" or an arrival
/// alert's notification take the rider to a tab without closing them, and the Plan button brings them back over the
/// planner, as 1.4.1's Plan tab kept its steps page. Null once the rider goes back from the steps, or plans afresh
/// from a stop or the map.
final openJourneyProvider = NotifierProvider<OpenJourneyNotifier, Journey?>(OpenJourneyNotifier.new);

class OpenJourneyNotifier extends Notifier<Journey?> {
  @override
  Journey? build() => null;

  void open(Journey journey) => state = journey;

  /// Closes [journey] (any open trip when null); a newer trip opened since stays open.
  void close([Journey? journey]) {
    if (journey == null || identical(state, journey)) state = null;
  }

  /// The open trip to bring back at [now], or null: one that has arrived is over, and is closed.
  Journey? stillUnderWay(DateTime now) {
    final j = state;
    if (j == null) return null;
    if (now.isAfter(j.at(j.arrives))) {
      state = null;
      return null;
    }
    return j;
  }
}

/// The live feed for plans, fetched again every 30 s while anything watches it (spec §3.4); null when unreadable.
///
/// Not while every listener is paused (the planner's pages, hidden behind another page): the refresh that falls due
/// then waits for a listener to resume, so a hidden screen that rebuilds reads the last answer instead of fetching,
/// and coming back fetches once.
final plannerLiveFeedProvider = FutureProvider.autoDispose<TimeTrackFetchResult?>((ref) async {
  var watched = true;
  var stale = false;
  ref.onCancel(() => watched = false);
  ref.onResume(() {
    watched = true;
    // Invalidating from inside the resume callback itself has no effect (as with the stop's arrivals).
    if (stale) scheduleMicrotask(() => ref.mounted ? ref.invalidateSelf() : null);
  });
  final timer = Timer(const Duration(seconds: 30), () {
    if (watched) {
      ref.invalidateSelf();
    } else {
      stale = true;
    }
  });
  ref.onDispose(timer.cancel);
  try {
    return await ref.read(timetrackApiProvider).fetchLiveVehiclesResult();
  } catch (_) {
    return null;
  }
});

/// The live feed as it is now: null until the first answer (or when it is unreadable), the last answer while the
/// next one loads. Plans don't wait for the feed; they are made again when a new answer comes (spec §3.4).
final _liveFeedNow = plannerLiveFeedProvider.select((f) => f.value);

/// Plans [q] with live times. When nothing runs later today on Leave by / Leave now, finds tomorrow's first bus.
Future<PlanOutcome> _plan(Ref ref, PlanQuery q, TimeTrackFetchResult? feed, DateTime now) async {
  final planner = await ref.watch(tripPlannerProvider(_day(q.time)).future);
  final outcome = planner.plan(q, now: now);
  if (outcome is PlanNoJourney && q.mode != PlanMode.arriveBy && q.from != q.to) {
    final tomorrow = DateTime(q.time.year, q.time.month, q.time.day + 1);
    final next = (await ref.watch(tripPlannerProvider(tomorrow).future))
        .plan(PlanQuery(from: q.from, to: q.to, mode: PlanMode.leaveBy, time: tomorrow));
    if (next is PlanFound && next.journeys.isNotEmpty) {
      final first = next.journeys.first;
      return PlanNoJourney(nextDeparture: first.at(first.departs));
    }
    return outcome;
  }
  if (outcome is! PlanFound) return outcome;
  // applyLive ranks its own result.
  final live = planner.applyLive(q, outcome.journeys, feed, now);
  if (live.isNotEmpty) return PlanFound(live);
  if (q.mode != PlanMode.arriveBy) return PlanNoJourney();
  // Arrive by, with every option past the deadline on live times: when could the rider get there, leaving now?
  final today = await ref.watch(tripPlannerProvider(_day(now)).future);
  final leaveNow = PlanQuery(from: q.from, to: q.to, mode: PlanMode.leaveBy, time: now);
  final soonest = today.plan(leaveNow, now: now);
  if (soonest is! PlanFound) return PlanNoJourney();
  final checked = today.applyLive(leaveNow, soonest.journeys, feed, now);
  if (checked.isEmpty) return PlanNoJourney();
  // Its look-back can find a late bus still to come that does make the deadline: that is an answer, not a miss.
  final deadline = secondsInServiceDay(today.index.serviceDate, q.time);
  final inTime = checked.where((j) => j.arrives <= deadline).toList();
  if (inTime.isNotEmpty) return PlanFound(rankJourneys(inTime, arriveBy: true));
  final first = checked.reduce((a, b) => a.arrives <= b.arrives ? a : b);
  return PlanNoJourney(firstArrival: first.at(first.arrives));
}

final planResultsProvider = FutureProvider.autoDispose<PlanOutcome?>((ref) async {
  final now = ref.read(plannerClockProvider)();
  final draft = ref.watch(planQueryProvider);
  final q = draft.toQuery(now, defaultTime: draft.usesDefaultTime ? ref.watch(planDefaultTimeProvider) : null);
  if (q == null) return null;
  return _plan(ref, q, ref.watch(_liveFeedNow), now);
});

final savedTripStoreProvider = Provider<SavedTripStore>((ref) => SavedTripStore());

class SavedTripsNotifier extends AsyncNotifier<List<SavedTrip>> {
  SavedTripStore get _store => ref.read(savedTripStoreProvider);

  /// The store reads, changes and writes the whole list, so changes run one at a time: a second tap
  /// waits for the first, and a failed change doesn't block the ones after it.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final run = _queue.catchError((_) {}).then((_) => op());
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<List<SavedTrip>> build() => _store.read();

  Future<bool> add(SavedTrip trip) => _serial(() async {
        final ok = await _store.add(trip);
        state = AsyncData(await _store.read());
        return ok;
      });

  Future<void> rename(String id, String name) => _serial(() async {
        await _store.rename(id, name);
        state = AsyncData(await _store.read());
      });

  Future<void> remove(String id) => _serial(() async {
        await _store.remove(id);
        state = AsyncData(await _store.read());
      });
}

final savedTripsProvider = AsyncNotifierProvider<SavedTripsNotifier, List<SavedTrip>>(SavedTripsNotifier.new);

/// A saved trip's next departures, leaving now, with live times (spec §3.5).
final savedTripNextProvider = FutureProvider.autoDispose.family<List<Journey>, String>((ref, id) async {
  final trips = await ref.watch(savedTripsProvider.future);
  final trip = trips.where((t) => t.id == id).firstOrNull;
  if (trip == null) return const [];
  final now = ref.read(plannerClockProvider)();
  final feed = ref.watch(_liveFeedNow);
  final out = await _plan(ref, PlanQuery(from: trip.from, to: trip.to, mode: PlanMode.leaveNow, time: now), feed, now);
  return out is PlanFound ? out.journeys.take(3).toList() : const [];
});

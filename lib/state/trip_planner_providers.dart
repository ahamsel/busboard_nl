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
final tripPlannerProvider = FutureProvider.autoDispose.family<TripPlanner, DateTime>((ref, day) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);
  final repo = await ref.watch(gtfsRepositoryProvider.future);
  return TripPlanner(repo, await ref.read(timetableIndexBuilderProvider)(repo, day));
});

/// What the Plan form holds.
class PlanDraft {
  const PlanDraft({this.from, this.to, this.mode = PlanMode.leaveNow, this.time});
  final Place? from;
  final Place? to;
  final PlanMode mode;
  final DateTime? time;

  PlanQuery? toQuery(DateTime now) => from == null || to == null
      ? null
      : PlanQuery(from: from!, to: to!, mode: mode, time: mode == PlanMode.leaveNow ? now : time ?? now);
}

class PlanQueryNotifier extends Notifier<PlanDraft> {
  @override
  PlanDraft build() => const PlanDraft();

  void setFrom(Place? p) => state = PlanDraft(from: p, to: state.to, mode: state.mode, time: state.time);
  void setTo(Place? p) => state = PlanDraft(from: state.from, to: p, mode: state.mode, time: state.time);
  void swap() => state = PlanDraft(from: state.to, to: state.from, mode: state.mode, time: state.time);
  void setMode(PlanMode m) => state = PlanDraft(from: state.from, to: state.to, mode: m, time: state.time);
  void setTime(DateTime t) => state = PlanDraft(from: state.from, to: state.to, mode: state.mode, time: t);

  /// A saved trip opened from its card: its ends, leaving now.
  void setTrip(Place from, Place to) => state = PlanDraft(from: from, to: to);
}

final planQueryProvider = NotifierProvider<PlanQueryNotifier, PlanDraft>(PlanQueryNotifier.new);

/// The live feed for plans, fetched again every 30 s while anything watches it (spec §3.4); null when unreadable.
final plannerLiveFeedProvider = FutureProvider.autoDispose<TimeTrackFetchResult?>((ref) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
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
  final q = ref.watch(planQueryProvider).toQuery(now);
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

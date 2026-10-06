// test/arrival_alerts/alert_replay_test.dart
//
// Replays recorded GTFS-RT through the Android watcher's path (spec §5) and scores the alerts against spec §1, with
// the bus's GPS passage at the stop as the real departure: at least 70% of attempted alerts within ±2 min of
// "passage − lead", at most 20% more than 2 min late, an alert that never fires is a failure, and at least 50 alerts
// scored. The stop-drop-off truth is printed for reference only. Record a capture with
// tool/capture_gtfsrt_alerts.dart, then:
//
//   TZ=America/St_Johns ALERT_CAPTURE=test/fixtures/timetrack/raw_gtfsrt_2026-10-05.jsonl \
//     ALERT_GTFS=build/gtfs_current flutter test test/arrival_alerts/alert_replay_test.dart
//
// GTFS service-day times are St. John's wall-clock times, and the app reads the feed's timestamps in the phone's
// local zone, so the capture test runs in America/St_Johns (the machine's zone, or `TZ=America/St_Johns`).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_tracker.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/domain/arrival_alerts/gtfs_rt_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ── Capture → polls ─────────────────────────────────────────────────────────────────────────────────────────────────

/// One trip's entry in a trip-updates poll: the stops still ahead, in order.
class TripListing {
  TripListing(this.seqs, this.stopIds, this.times, this.delays);

  /// Marks a stop whose update has no delay.
  static const noDelay = -0x80000000;

  final Int32List seqs;
  final List<String> stopIds;

  /// The feed's predicted time at each stop, in epoch seconds (0 when the feed gave none).
  final Int64List times;

  /// The feed's delay at each stop, in seconds ([noDelay] when the feed gave none).
  final Int32List delays;

  int indexOf(int seq) {
    for (var i = 0; i < seqs.length; i++) {
      if (seqs[i] == seq) return i;
    }
    return -1;
  }
}

/// One recorded poll. Every poll keeps its trip listings (the departure truth, at full resolution); a replayed poll
/// (one per 30 s, as the watcher checks) also keeps what the production fetch made of it.
class ReplayPoll {
  ReplayPoll(this.at, this.trips, this.feed);

  /// The poll's `fetch_time` on the local clock, in whole milliseconds as an alert keeps them.
  final DateTime at;

  /// Trip id → listing; null when the trip-updates feed failed on this poll.
  final Map<String, TripListing>? trips;

  /// `TimeTrackApi.fetchLiveVehiclesResult()` for this poll; null when the poll is not replayed.
  final TimeTrackFetchResult? feed;

  bool get replayed => feed != null;
}

/// A capture's `fetch_time` (UTC) as the phone's clock reads it.
DateTime pollTimeOf(String fetchTime) =>
    DateTime.fromMillisecondsSinceEpoch(DateTime.parse(fetchTime).millisecondsSinceEpoch);

FeedMessage? _feedOf(Object? json) {
  // A failed fetch is recorded as null (older captures used {"error": …} or {"status_code": …}).
  if (json is! Map<String, dynamic> || !json.containsKey('header')) return null;
  return FeedMessage()..mergeFromProto3Json(json);
}

/// Serves one poll's two feeds to the production client, as protobuf bytes; a missing feed answers 503.
http.Client _clientFor(List<int>? positions, List<int>? updates) => MockClient((request) async {
  final path = request.url.path;
  final body = path.endsWith('/gtfsrt/vehiclepositions')
      ? positions
      : path.endsWith('/gtfsrt/tripupdates')
      ? updates
      : null;
  return body == null ? http.Response('', 503) : http.Response.bytes(body, 200);
});

/// The watcher's check interval; a capture's polls are replayed at this cadence.
const watcherCadence = Duration(seconds: 30);

/// One GPS fix of a trip's vehicle, in epoch seconds.
class Fix {
  const Fix(this.t, this.lat, this.lon);

  final int t;
  final double lat, lon;
}

/// Reads a capture's JSON lines one at a time and replays one poll per [watcherCadence] through the production fetch:
/// every 3rd poll of a 10 s capture, every poll of a 30 s one (tool/capture_gtfsrt_alerts.dart).
///
/// When [fixes] is given, it is filled with every trip's distinct GPS fixes from every poll, in time order.
Future<List<ReplayPoll>> loadCapture(Stream<String> lines, {Map<String, List<Fix>>? fixes}) async {
  final byTrip = <String, Map<int, Fix>>{};
  final pool = <String, String>{}; // one copy of each stop id across ~1.7 M listings
  final polls = <ReplayPoll>[];
  DateTime? lastReplayed;
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    final at = pollTimeOf(j['fetch_time'] as String);
    final positions = _feedOf(j['vehicle_positions']);
    final updates = _feedOf(j['trip_updates']);

    if (fixes != null && positions != null) {
      for (final e in positions.entity) {
        final v = e.vehicle;
        if (!e.hasVehicle() || !v.hasPosition() || !v.hasTimestamp() || v.trip.tripId.isEmpty) continue;
        final t = v.timestamp.toInt();
        (byTrip[v.trip.tripId] ??= {})[t] ??= Fix(t, v.position.latitude, v.position.longitude);
      }
    }

    Map<String, TripListing>? trips;
    if (updates != null) {
      trips = {};
      for (final e in updates.entity) {
        if (!e.hasTripUpdate() || e.tripUpdate.trip.tripId.isEmpty) continue;
        final stops = e.tripUpdate.stopTimeUpdate;
        final seqs = Int32List(stops.length), times = Int64List(stops.length), delays = Int32List(stops.length);
        final ids = List<String>.filled(stops.length, '');
        for (var k = 0; k < stops.length; k++) {
          final s = stops[k];
          seqs[k] = s.stopSequence;
          ids[k] = pool.putIfAbsent(s.stopId, () => s.stopId);
          final ev = s.hasDeparture() && s.departure.hasTime()
              ? s.departure
              : s.hasArrival() && s.arrival.hasTime()
              ? s.arrival
              : null;
          times[k] = ev == null ? 0 : ev.time.toInt();
          final withDelay = s.hasDeparture() && s.departure.hasDelay()
              ? s.departure
              : s.hasArrival() && s.arrival.hasDelay()
              ? s.arrival
              : null;
          delays[k] = withDelay == null ? TripListing.noDelay : withDelay.delay;
        }
        trips[e.tripUpdate.trip.tripId] = TripListing(seqs, ids, times, delays);
      }
    }

    TimeTrackFetchResult? feed;
    // A few seconds of slack absorb the recorder's jitter: 10.004 s polls still replay every 3rd.
    if (lastReplayed == null || at.difference(lastReplayed) >= watcherCadence - const Duration(seconds: 5)) {
      lastReplayed = at;
      final api = TimeTrackApi(client: _clientFor(positions?.writeToBuffer(), updates?.writeToBuffer()));
      feed = await api.fetchLiveVehiclesResult();
    }
    polls.add(ReplayPoll(at, trips, feed));
  }
  if (fixes != null) {
    byTrip.forEach((trip, m) => fixes[trip] = m.values.toList()..sort((a, b) => a.t.compareTo(b.t)));
  }
  return polls;
}

// ── Static schedule ─────────────────────────────────────────────────────────────────────────────────────────────────

/// GTFS stop_times by (trip, stop sequence), with each trip's route and headsign.
class TripSchedule {
  TripSchedule(GtfsRepository repo, Set<String> tripIds) : _repo = repo {
    for (final rows in repo.stopTimesByStopId.values) {
      for (final st in rows) {
        if (tripIds.contains(st.tripId)) (_rows[st.tripId] ??= {})[st.stopSequence] = st;
      }
    }
  }

  final GtfsRepository _repo;
  final _rows = <String, Map<int, StopTimeRow>>{};

  StopTimeRow? stopTime(String trip, int seq) => _rows[trip]?[seq];

  String routeOf(String trip) {
    final routeId = _repo.tripsById[trip]?.routeId ?? '';
    return _repo.routesById[routeId]?.routeShortName ?? routeId;
  }

  String headsignOf(String trip) => _repo.tripsById[trip]?.tripHeadsign ?? '';
  String stopNameOf(String stop) => _repo.stopsById[stop]?.stopName ?? stop;
  StopInfo? stopOf(String stop) => _repo.stopsById[stop];
}

// ── Real departures ─────────────────────────────────────────────────────────────────────────────────────────────────

enum DepartureKind { passed, vanished, ghost, captureEnded }

/// A stop's real departure, read from the trip-updates feed at full resolution from poll [from] on.
///
/// - **passed:** the first poll where the trip is listed but the stop is not (the bus went by).
/// - **vanished:** the trip left the feed with the stop due within 5 min; the departure is the first poll without
///   the trip. A trip that drops out and comes back still listing the stop has not vanished.
/// - **ghost:** the trip left the feed with the stop predicted more than 5 min ahead. Not scored.
/// - **captureEnded:** the stop was still listed at the end. Not scored.
({DepartureKind kind, DateTime? at}) departureOf(List<ReplayPoll> polls, int from, String trip, int seq) {
  var predicted = 0;
  int? dropped;
  ({DepartureKind kind, DateTime? at}) vanish(int d) {
    final at = polls[d].at;
    final ahead = Duration(seconds: predicted - at.millisecondsSinceEpoch ~/ 1000);
    return predicted != 0 && ahead > const Duration(minutes: 5)
        ? (kind: DepartureKind.ghost, at: null)
        : (kind: DepartureKind.vanished, at: at);
  }

  for (var j = from; j < polls.length; j++) {
    final trips = polls[j].trips;
    if (trips == null) continue; // the feed failed: nothing known
    final listing = trips[trip];
    if (listing == null) {
      dropped ??= j;
      continue;
    }
    final k = listing.indexOf(seq);
    if (k >= 0) {
      predicted = listing.times[k];
      dropped = null;
      continue;
    }
    if (dropped != null) return vanish(dropped);
    return (kind: DepartureKind.passed, at: polls[j].at);
  }
  if (dropped != null) return vanish(dropped);
  return (kind: DepartureKind.captureEnded, at: null);
}

// ── Scoring ─────────────────────────────────────────────────────────────────────────────────────────────────────────

enum Outcome { fired, unfired, ghost, captureEnded, setTooLate }

class AlertRecord {
  AlertRecord({
    required this.trip,
    required this.route,
    required this.stopId,
    required this.seq,
    required this.lead,
    required this.setAt,
    required this.scheduledAt,
    required this.expectedAt,
    required this.outcome,
    this.departure,
    this.firedAt,
  });

  final String trip, route, stopId;
  final int seq, lead;
  final DateTime setAt, scheduledAt;

  /// The app's prediction when the alert was set.
  final DateTime expectedAt;
  final Outcome outcome;
  final DateTime? departure, firedAt;

  DateTime? get target => departure?.subtract(Duration(minutes: lead));
  Duration? get error => firedAt == null || target == null ? null : firedAt!.difference(target!);
}

class ReplaySummary {
  ReplaySummary(this.records);

  final List<AlertRecord> records;

  Iterable<AlertRecord> _of(Outcome o, [int? lead]) =>
      records.where((r) => r.outcome == o && (lead == null || r.lead == lead));

  List<Duration> errors([int? lead]) => [for (final r in _of(Outcome.fired, lead)) r.error!];
  int count(Outcome o, [int? lead]) => _of(o, lead).length;
  int attempted([int? lead]) => count(Outcome.fired, lead) + count(Outcome.unfired, lead);
  int within([int? lead]) => errors(lead).where((e) => e.inSeconds.abs() <= 60).length;
  double withinShare([int? lead]) => attempted(lead) == 0 ? 0 : within(lead) / attempted(lead);
  int? worstLate([int? lead]) {
    final e = errors(lead);
    return e.isEmpty ? null : e.map((d) => d.inSeconds).reduce((a, b) => a > b ? a : b);
  }

  int? _abs(double q, [int? lead]) {
    final a = errors(lead).map((e) => e.inSeconds.abs()).toList()..sort();
    return a.isEmpty ? null : a[((a.length - 1) * q).round()];
  }

  int? medianAbs([int? lead]) => _abs(0.5, lead);
  int? p90Abs([int? lead]) => _abs(0.9, lead);

  String _line([int? lead]) =>
      'attempted ${attempted(lead)}, fired ${count(Outcome.fired, lead)}, '
      'unfired ${count(Outcome.unfired, lead)}, within ±60 s ${within(lead)} '
      '(${(withinShare(lead) * 100).toStringAsFixed(1)}%), worst late ${worstLate(lead) ?? '-'} s, '
      'median |error| ${medianAbs(lead) ?? '-'} s, p90 |error| ${p90Abs(lead) ?? '-'} s, '
      'ghosts ${count(Outcome.ghost, lead)}, set too late ${count(Outcome.setTooLate, lead)}, '
      'capture ended ${count(Outcome.captureEnded, lead)}';

  String format() => ['alerts: ${_line()}', for (final l in alertLeadChoices) '  lead $l min: ${_line(l)}'].join('\n');

  List<AlertRecord> worst(int n) =>
      (records.where((r) => r.error != null || r.outcome == Outcome.unfired).toList()..sort((a, b) {
            int key(AlertRecord r) => r.error?.inSeconds.abs() ?? 1 << 30; // unfired first
            return key(b).compareTo(key(a));
          }))
          .take(n)
          .toList();

  String csv() {
    String t(DateTime? d) => d?.toIso8601String() ?? '';
    return [
      'trip,route,stop,seq,lead,set_time,scheduled,expected_at_set,departure,target,fire_time,error_s,outcome',
      for (final r in records)
        [
          r.trip,
          r.route,
          r.stopId,
          r.seq,
          r.lead,
          t(r.setAt),
          t(r.scheduledAt),
          t(r.expectedAt),
          t(r.departure),
          t(r.target),
          t(r.firedAt),
          r.error?.inSeconds ?? '',
          r.outcome.name,
        ].join(','),
    ].join('\n');
  }
}

/// Up to three stops of a listing, spread out: the first at least 11 min ahead (else the first), the last, and the
/// one midway between them.
List<int> pickStops(List<DateTime?> predicted, DateTime now) {
  final known = [
    for (var k = 0; k < predicted.length; k++)
      if (predicted[k] != null) k,
  ];
  if (known.isEmpty) return const [];
  final first = known.firstWhere(
    (k) => predicted[k]!.difference(now) >= const Duration(minutes: 11),
    orElse: () => known.first,
  );
  final last = known.last;
  final mid = known.firstWhere((k) => k >= (first + last) ~/ 2, orElse: () => last);
  return {first, mid, last}.toList()..sort();
}

/// One alert as a rider would set it from the Board at a poll. Every variant runs the same population.
class AlertSetup {
  AlertSetup({
    required this.alert,
    required this.route,
    required this.seq,
    required this.setIndex,
    required this.dropOff,
    required this.tooLate,
  });

  /// As `ArrivalAlert.fromArrival` builds it, with the production prediction as `expectedAt`.
  final ArrivalAlert alert;
  final String route;
  final int seq;

  /// The poll it was set at.
  final int setIndex;

  /// The stop-drop-off departure truth.
  final ({DepartureKind kind, DateTime? at}) dropOff;

  /// The app would not offer this lead for the prediction's minutes away (`leadChoicesFor`).
  final bool tooLate;

  String get trip => alert.tripId;
  String get stopId => alert.stopId;
  int get lead => alert.leadMinutes;
  DateTime get setAt => alert.setAt;
}

/// The alerts to set: for each trip in the trip-updates feed, at the first replayed poll where the adapter gives it a
/// live row, up to three of its listed stops ([pickStops]), each with every lead time.
List<AlertSetup> setupAlerts(List<ReplayPoll> polls, TripSchedule schedule) {
  final setups = <AlertSetup>[];
  final seen = <String>{};
  for (var i = 0; i < polls.length; i++) {
    final poll = polls[i];
    if (!poll.replayed || poll.trips == null) continue;
    final now = poll.at;
    poll.trips!.forEach((trip, listing) {
      if (seen.contains(trip)) return;
      ArrivalAlert alertFor(int k, int lead, DateTime scheduledAt, DateTime expectedAt, String? vehicle) =>
          ArrivalAlert(
            stopId: listing.stopIds[k],
            stopName: schedule.stopNameOf(listing.stopIds[k]),
            routeShortName: schedule.routeOf(trip),
            headsign: schedule.headsignOf(trip),
            tripId: trip,
            vehicle: vehicle,
            scheduledAt: scheduledAt,
            expectedAt: expectedAt,
            live: true,
            leadMinutes: lead,
            setAt: now,
            lastSeenAt: now,
          );

      // The app's prediction at each listed stop, as the Board would show it now.
      final scheduled = <DateTime?>[];
      final predicted = <DateTime?>[];
      String? vehicle;
      for (var k = 0; k < listing.seqs.length; k++) {
        final st = schedule.stopTime(trip, listing.seqs[k]);
        final s = st == null ? null : instantOfServiceTime(GtfsTime.parse(st.departureTime), now);
        scheduled.add(s);
        if (s == null) {
          predicted.add(null);
          continue;
        }
        // The adapter's live row for an alert on this stop, as the production watcher would get it.
        final rows = liveResultForAlert(alertFor(k, alertLeadChoices.first, s, s, null), poll.feed, now).departures;
        final g = rows.isEmpty ? null : (rows.first.predictedGtfsTime ?? rows.first.scheduledGtfsTime);
        if (rows.isNotEmpty) vehicle = rows.first.vehicle;
        predicted.add(g == null ? null : instantOfServiceTime(g, now));
      }
      if (predicted.every((p) => p == null)) return; // not live yet: try a later poll
      seen.add(trip);

      for (final k in pickStops(predicted, now)) {
        final seq = listing.seqs[k];
        final p = predicted[k]!;
        final dropOff = departureOf(polls, i, trip, seq);
        for (final lead in alertLeadChoices) {
          setups.add(
            AlertSetup(
              alert: alertFor(k, lead, scheduled[k]!, p, vehicle),
              route: schedule.routeOf(trip),
              seq: seq,
              setIndex: i,
              dropOff: dropOff,
              tooLate: !leadChoicesFor(p.difference(now).inMinutes).contains(lead),
            ),
          );
        }
      }
    });
  }
  return setups;
}

// ── Prediction variants (the experiment) ───────────────────────────────────────────────────────────────────────────

/// What feeds `AlertTracker.step` at a replayed poll.
typedef RowSource = MetrobusDeparturesResult Function(ArrivalAlert alert, ReplayPoll poll);

/// A way of predicting and firing, run on the same alerts as production.
class Variant {
  const Variant(this.name, this.source, {this.confirmTwice = false});

  final String name;

  /// A fresh source for each alert (a smoothing source keeps that alert's history).
  final RowSource Function(AlertSetup setup) source;

  /// Fire only when the tracker's fire decision holds on two replayed polls in a row; the alert time is the second.
  final bool confirmTwice;
}

/// The production path: the adapter, which reads the trip update's own time at the alert's stop.
MetrobusDeparturesResult productionRows(ArrivalAlert alert, ReplayPoll poll) =>
    liveResultForAlert(alert, poll.feed, poll.at);

/// A: the adapter without per-stop times, so every prediction is scheduled − the vehicle's schedule difference
/// (production before the accuracy fix, and what the iPhone's Board rows carry).
MetrobusDeparturesResult schedDiffRows(ArrivalAlert alert, ReplayPoll poll) {
  final feed = poll.feed;
  final stripped = feed == null || !feed.succeeded
      ? feed
      : TimeTrackFetchResult.success(feed.vehicles, source: feed.source!);
  return liveResultForAlert(alert, stripped, poll.at);
}

/// The feed's own prediction for stop [seq] of [trip] at [poll]: its `time`, else the timetable plus its `delay`.
DateTime? feedStopTime(ReplayPoll poll, String trip, int seq, DateTime scheduledAt) {
  final listing = poll.trips?[trip];
  final k = listing?.indexOf(seq) ?? -1;
  if (k < 0) return null;
  if (listing!.times[k] != 0) return DateTime.fromMillisecondsSinceEpoch(listing.times[k] * 1000);
  if (listing.delays[k] != TripListing.noDelay) return scheduledAt.add(Duration(seconds: listing.delays[k]));
  return null;
}

/// [r] with its one live row predicted at [predictedSeconds] (service-day seconds, as the row counts them).
MetrobusDeparturesResult _withPredicted(MetrobusDeparturesResult r, int predictedSeconds) {
  final d = r.departures.first;
  return MetrobusDeparturesResult(
    departures: [
      MetrobusDeparture(
        routeRun: d.routeRun,
        routeShortName: d.routeShortName,
        vehicle: d.vehicle,
        scheduledTime: d.scheduledTime,
        predictedTime: d.predictedTime,
        headsign: d.headsign,
        currentLocation: d.currentLocation,
        isTracked: d.isTracked,
        tripId: d.tripId,
        scheduledDepartureSeconds: d.scheduledDepartureSeconds,
        predictedDepartureSeconds: predictedSeconds,
        isRealtime: d.isRealtime,
      ),
    ],
    succeeded: r.succeeded,
    realtimeAvailable: r.realtimeAvailable,
    serviceOperating: r.serviceOperating,
    fetchedAt: r.fetchedAt,
  );
}

/// C: A's live row, re-timed to the feed's own prediction for the alert's stop sequence when the poll lists it (the
/// experiment's version of what production now does by stop id).
RowSource perStopRows(int seq) => (alert, poll) {
  final r = schedDiffRows(alert, poll);
  if (r.departures.isEmpty || r.departures.first.scheduledDepartureSeconds == null) return r;
  final at = feedStopTime(poll, alert.tripId, seq, alert.scheduledAt);
  if (at == null) return r; // the stop has no update: A's prediction
  // Keep the row's service-day counting: its scheduled seconds, moved by the feed's offset from the timetable.
  return _withPredicted(r, r.departures.first.scheduledDepartureSeconds! + at.difference(alert.scheduledAt).inSeconds);
};

/// E: [inner]'s prediction smoothed as the median of the last 3 polls that had one.
RowSource smoothedRows(RowSource inner) {
  final history = <int>[];
  return (alert, poll) {
    final r = inner(alert, poll);
    final p = r.departures.isEmpty ? null : r.departures.first.predictedDepartureSeconds;
    if (p == null) return r;
    history.add(p);
    if (history.length > 3) history.removeAt(0);
    final s = [...history]..sort();
    return _withPredicted(r, s.length == 2 ? (s[0] + s[1]) ~/ 2 : s[s.length ~/ 2]);
  };
}

/// What ships: the adapter's per-stop time (variant C, matched by stop id).
final production = Variant('production', (_) => productionRows);

/// Undoes `alertEarlyMargin` for a live prediction: the tracker fires 60 s before expected − lead, so a prediction
/// 60 s later fires at expected − lead, as A–E did before the margin. (A timetable or lost step is not shifted.)
RowSource withoutMargin(RowSource inner) => shiftedRows(inner, alertEarlyMargin.inSeconds);

final variants = <Variant>[
  Variant('A schedule diff', (_) => withoutMargin(schedDiffRows)),
  Variant('B confirm twice', (_) => withoutMargin(schedDiffRows), confirmTwice: true),
  Variant('C per-stop time', (s) => withoutMargin(perStopRows(s.seq))),
  Variant('D B+C', (s) => withoutMargin(perStopRows(s.seq)), confirmTwice: true),
  Variant('E C, median of 3', (s) => withoutMargin(smoothedRows(perStopRows(s.seq)))),
  // The margin, tuned in-sample on the 10-05 capture (about C's and A's median lateness); a second capture must
  // confirm it. F is what ships on Android, G what the iPhone's Board rows give.
  Variant('F production (C − 60 s)', (_) => productionRows),
  Variant('G A − 60 s (iPhone)', (_) => schedDiffRows),
];

/// [inner]'s prediction moved by [seconds].
RowSource shiftedRows(RowSource inner, int seconds) => (alert, poll) {
  final r = inner(alert, poll);
  final p = r.departures.isEmpty ? null : r.departures.first.predictedDepartureSeconds;
  return p == null ? r : _withPredicted(r, p + seconds);
};

ArrivalAlert _unfired(ArrivalAlert a) => ArrivalAlert(
  stopId: a.stopId,
  stopName: a.stopName,
  routeShortName: a.routeShortName,
  headsign: a.headsign,
  tripId: a.tripId,
  routeRun: a.routeRun,
  vehicle: a.vehicle,
  scheduledAt: a.scheduledAt,
  expectedAt: a.expectedAt,
  live: a.live,
  leadMinutes: a.leadMinutes,
  setAt: a.setAt,
  lastSeenAt: a.lastSeenAt,
);

/// Steps the production tracker from the set poll on, at each replayed poll, until it fires (the fire time) or
/// finishes or the capture ends (null).
DateTime? runAlert(AlertSetup setup, List<ReplayPoll> polls, Variant variant) {
  const tracker = AlertTracker();
  final source = variant.source(setup);
  var alert = setup.alert;
  var armed = false;
  for (var j = setup.setIndex; j < polls.length; j++) {
    final q = polls[j];
    if (!q.replayed) continue;
    final s = tracker.step(alert, source(alert, q), q.at);
    if (s.fire) {
      if (!variant.confirmTwice || armed) return q.at;
      armed = true;
      alert = _unfired(s.alert); // re-timed, but not fired yet
      continue;
    }
    armed = false;
    alert = s.alert;
    if (s.finished) return null;
  }
  return null;
}

/// Sets and runs alerts for every trip in [polls] on the production path and scores them against the stop-drop-off
/// truth (spec §1).
ReplaySummary replayAlerts(List<ReplayPoll> polls, TripSchedule schedule) {
  final records = <AlertRecord>[];
  for (final s in setupAlerts(polls, schedule)) {
    AlertRecord record(Outcome o, {DateTime? firedAt}) => AlertRecord(
      trip: s.trip,
      route: s.route,
      stopId: s.stopId,
      seq: s.seq,
      lead: s.lead,
      setAt: s.setAt,
      scheduledAt: s.alert.scheduledAt,
      expectedAt: s.alert.expectedAt,
      outcome: o,
      departure: s.dropOff.at,
      firedAt: firedAt,
    );
    if (s.tooLate) {
      records.add(record(Outcome.setTooLate));
    } else if (s.dropOff.kind == DepartureKind.ghost) {
      records.add(record(Outcome.ghost));
    } else if (s.dropOff.kind == DepartureKind.captureEnded) {
      records.add(record(Outcome.captureEnded));
    } else {
      final firedAt = runAlert(s, polls, production);
      final target = s.dropOff.at!.subtract(Duration(minutes: s.lead));
      records.add(
        firedAt != null
            ? record(Outcome.fired, firedAt: firedAt)
            : record(target.isAfter(polls.last.at) ? Outcome.captureEnded : Outcome.unfired),
      );
    }
  }
  return ReplaySummary(records);
}

// ── GPS truth ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// When the trip's bus passed the stop at ([lat], [lon]), from its GPS fixes.
///
/// A visit is a run of fixes that comes within 60 m of the stop and ends when the bus is more than 150 m away; its
/// passage is the fix closest to the stop, interpolated along the track to the point nearest the stop. Visits from
/// 5 min before [from] on count. A trip can pass a stop twice (out and back on one street, or a loop), and a stop
/// leaves the feed's predictions only after the bus passed it, so with [until] (the stop-drop-off time) the passage
/// is the last visit before it, else the first. Null when no fix comes within 60 m.
DateTime? gpsPassage(List<Fix> fixes, double lat, double lon, DateTime from, {DateTime? until}) {
  final since = from.millisecondsSinceEpoch ~/ 1000 - 300;
  final cosLat = math.cos(lat * math.pi / 180);
  (double, double) xy(Fix f) => ((f.lon - lon) * cosLat * 111320, (f.lat - lat) * 110540);
  double dist(Fix f) {
    final (x, y) = xy(f);
    return math.sqrt(x * x + y * y);
  }

  // The segment either side of the closest fix whose nearest point to the stop lies inside it, and is nearest.
  DateTime passage(int best, double bestD) {
    var at = fixes[best].t.toDouble();
    var nearest = bestD;
    for (final (a, b) in [(best - 1, best), (best, best + 1)]) {
      if (a < 0 || b >= fixes.length) continue;
      final (ax, ay) = xy(fixes[a]);
      final (bx, by) = xy(fixes[b]);
      final vx = bx - ax, vy = by - ay, len2 = vx * vx + vy * vy;
      if (len2 < 1) continue;
      final u = -(ax * vx + ay * vy) / len2;
      if (u < 0 || u > 1) continue;
      final px = ax + u * vx, py = ay + u * vy, d = math.sqrt(px * px + py * py);
      if (d < nearest) {
        nearest = d;
        at = fixes[a].t + u * (fixes[b].t - fixes[a].t);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch((at * 1000).round());
  }

  final visits = <DateTime>[];
  int? best;
  var bestD = double.infinity;
  for (var i = 0; i < fixes.length; i++) {
    if (fixes[i].t < since) continue;
    final d = dist(fixes[i]);
    if (best == null) {
      if (d <= 60) (best, bestD) = (i, d);
    } else if (d < bestD) {
      (best, bestD) = (i, d);
    } else if (d > 150) {
      visits.add(passage(best, bestD)); // left the stop: the visit is over
      (best, bestD) = (null, double.infinity);
    }
  }
  if (best != null) visits.add(passage(best, bestD));
  if (visits.isEmpty) return null;
  if (until == null) return visits.first;
  // The drop-off is polled every 10 s and the fixes are a little older than the poll: a minute of slack.
  final before = visits.where((v) => !v.isAfter(until.add(const Duration(minutes: 1))));
  return before.isEmpty ? null : before.last;
}

// ── Scoring against the GPS passage ─────────────────────────────────────────────────────────────────────────────────

/// One alert under one variant, against one truth. [error] is null when it never fired (a failure).
class Trial {
  Trial(this.setup, this.error);

  final AlertSetup setup;
  final Duration? error;
}

/// The stop-drop-off departure, when the capture has one.
DateTime? dropOffTruth(AlertSetup s) =>
    s.dropOff.kind == DepartureKind.passed || s.dropOff.kind == DepartureKind.vanished ? s.dropOff.at : null;

/// Each alert's GPS passage ([gpsPassage], anchored on the drop-off when there is one), with the alerts left out:
/// no fix within 60 m, or the bus had already passed when the alert was set.
({Map<AlertSetup, DateTime> at, int noFix, int passedBefore}) gpsTruths(
  List<AlertSetup> setups,
  TripSchedule schedule,
  Map<String, List<Fix>> fixes,
) {
  final at = <AlertSetup, DateTime>{};
  var noFix = 0, passedBefore = 0;
  for (final s in setups) {
    final stop = schedule.stopOf(s.stopId);
    final g = stop == null
        ? null
        : gpsPassage(fixes[s.trip] ?? const [], stop.stopLat, stop.stopLon, s.setAt, until: dropOffTruth(s));
    if (g == null) {
      noFix++;
    } else if (!g.isAfter(s.setAt)) {
      passedBefore++;
    } else {
      at[s] = g;
    }
  }
  return (at: at, noFix: noFix, passedBefore: passedBefore);
}

/// Spec §1's score: [trials] are the attempted alerts, and one that never fired is a failure.
class GpsScore {
  GpsScore(this.trials);

  final List<Trial> trials;

  int get attempted => trials.length;
  int get unfired => trials.where((t) => t.error == null).length;

  /// Fired within ±2 min of passage − lead.
  int get within => trials.where((t) => t.error != null && t.error!.inSeconds.abs() <= 120).length;

  /// Fired more than 2 min after passage − lead.
  int get late => trials.where((t) => t.error != null && t.error!.inSeconds > 120).length;

  double get withinShare => attempted == 0 ? 0 : within / attempted;
  double get lateShare => attempted == 0 ? 0 : late / attempted;

  /// At least 50 scored, at least 70% within ±2 min, at most 20% more than 2 min late.
  bool get meetsCriterion => attempted >= 50 && withinShare >= 0.7 && lateShare <= 0.2;

  String format() =>
      'attempted $attempted, unfired $unfired, within ±2 min $within (${(withinShare * 100).toStringAsFixed(1)}%), '
      'late > 2 min $late (${(lateShare * 100).toStringAsFixed(1)}%): '
      '${meetsCriterion ? 'meets' : 'does not meet'} §1 (≥ 50 scored, ≥ 70% within, ≤ 20% late)';
}

/// The accuracy columns for a set of trials.
String accuracyRow(String label, List<Trial> trials) {
  final n = trials.length;
  if (n == 0) return '${label.padRight(22)} n 0';
  final e = [
    for (final t in trials)
      if (t.error != null) t.error!.inSeconds,
  ];
  final abs = e.map((x) => x.abs()).toList()..sort();
  String pct(int k) => '${(100 * k / n).toStringAsFixed(1)}%'.padLeft(6);
  String q(double f) => abs.isEmpty ? '-' : '${abs[((abs.length - 1) * f).round()]}';
  final early = e.isEmpty ? '-' : '${e.reduce(math.min)}';
  final signed = [...e]..sort();
  final bias = signed.isEmpty ? '-' : '${signed[(signed.length - 1) ~/ 2]}';
  final late = e.isEmpty ? '-' : '${e.reduce(math.max)}';
  return [
    label.padRight(22),
    '$n'.padLeft(5),
    '${n - e.length}'.padLeft(4),
    pct(e.where((x) => x.abs() <= 60).length),
    pct(e.where((x) => x.abs() <= 120).length),
    q(0.5).padLeft(5),
    q(0.9).padLeft(5),
    bias.padLeft(5),
    early.padLeft(6),
    late.padLeft(5),
    pct(e.where((x) => x > 120).length),
  ].join(' ');
}

const accuracyHeader = 'variant / lead             n  unf  ±60s  ±120s  med|e| p90|e|  bias  early  late late>120';

/// The experiment: every variant on the same alerts, scored against the GPS passage and the stop-drop-off truth.
String accuracyExperiment(List<ReplayPoll> polls, TripSchedule schedule, Map<String, List<Fix>> fixes) {
  final setups = setupAlerts(polls, schedule).where((s) => !s.tooLate).toList();
  final (at: gps, noFix: noGps, :passedBefore) = gpsTruths(setups, schedule, fixes);
  final fired = {
    for (final v in variants) v: {for (final s in setups) s: runAlert(s, polls, v)},
  };

  List<Trial> trials(Variant v, DateTime? Function(AlertSetup) truth, bool Function(AlertSetup) keep) => [
    for (final s in setups)
      if (keep(s) && truth(s) != null)
        Trial(s, fired[v]![s]?.difference(truth(s)!.subtract(Duration(minutes: s.lead)))),
  ];
  bool all(AlertSetup _) => true;
  bool tenAhead(AlertSetup s) => s.alert.expectedAt.difference(s.setAt) >= const Duration(minutes: 10);

  final out = StringBuffer()
    ..writeln(
      'experiment: ${setups.length} alerts set; GPS truth ${gps.length}, no GPS fix within 60 m $noGps, '
      'bus passed before the alert was set $passedBefore; drop-off truth '
      '${setups.where((s) => dropOffTruth(s) != null).length}',
    );
  for (final (subset, keep) in [('all alerts', all), ('set at least 10 min ahead', tenAhead)]) {
    for (final (truthName, truth) in [('GPS passage', (AlertSetup s) => gps[s]), ('stop drop-off', dropOffTruth)]) {
      out
        ..writeln(
          '\n$subset, truth = $truthName (errors in s, + is late; bias = median error; late>120 is a share of n)',
        )
        ..writeln(accuracyHeader);
      for (final v in variants) {
        out.writeln(accuracyRow(v.name, trials(v, truth, keep)));
        for (final lead in alertLeadChoices) {
          out.writeln(accuracyRow('  lead $lead', trials(v, truth, (s) => keep(s) && s.lead == lead)));
        }
      }
    }
  }
  String hms(DateTime? t) => t == null ? '-' : t.toIso8601String().substring(11, 19);
  out.writeln('\nworst 3 against the GPS passage, per variant:');
  for (final v in variants) {
    final worst = trials(v, (s) => gps[s], all)
      ..sort((a, b) {
        int key(Trial t) => t.error?.inSeconds.abs() ?? 1 << 30; // unfired first
        return key(b).compareTo(key(a));
      });
    for (final t in worst.take(3)) {
      final s = t.setup;
      out.writeln(
        '  ${v.name}: trip ${s.trip} rt ${s.route} stop ${s.stopId} (seq ${s.seq}) lead ${s.lead}: set ${hms(s.setAt)}, '
        'predicted at set ${hms(s.alert.expectedAt)}, GPS ${hms(gps[s])}, drop-off ${hms(dropOffTruth(s))}, '
        'fired ${hms(fired[v]![s])}, error ${t.error?.inSeconds ?? 'unfired'} s',
      );
    }
  }
  return out.toString();
}

// ── Synthetic polls ─────────────────────────────────────────────────────────────────────────────────────────────────

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Map<String, Object?> _header(DateTime at) => {
  'gtfsRealtimeVersion': '2.0',
  'incrementality': 'FULL_DATASET',
  'timestamp': '${_epoch(at)}',
};

/// One synthetic poll in the capture's line format. [stops] lists the trip's stops still ahead as
/// (sequence, stop id, scheduled time); null means the trip and its bus are not in the feeds.
String _pollLine(
  DateTime at, {
  required String trip,
  required List<(int, String, DateTime)>? stops,
  int Function(int seq)? delayOf,
}) {
  int delay(int seq) => delayOf?.call(seq) ?? 180;
  final vehicles = [
    if (stops != null)
      {
        'id': '1415',
        'vehicle': {
          'trip': {'tripId': trip, 'routeId': '10'},
          'position': {'latitude': 47.57, 'longitude': -52.73},
          'timestamp': '${_epoch(at) - 5}',
          'vehicle': {'id': '1415'},
        },
      },
  ];
  final updates = [
    if (stops != null)
      {
        'id': trip,
        'tripUpdate': {
          'trip': {'tripId': trip, 'routeId': '10'},
          'stopTimeUpdate': [
            for (final (seq, stop, scheduled) in stops)
              {
                'stopSequence': seq,
                'stopId': stop,
                'arrival': {'delay': delay(seq), 'time': '${_epoch(scheduled) + delay(seq)}'},
                'departure': {'delay': delay(seq), 'time': '${_epoch(scheduled) + delay(seq)}'},
              },
          ],
        },
      },
  ];
  return jsonEncode({
    'fetch_time': at.toUtc().toIso8601String(),
    'vehicle_positions': {'header': _header(at), 'entity': vehicles},
    'trip_updates': {'header': _header(at), 'entity': updates},
  });
}

String _clock(DateTime t) => [t.hour, t.minute, t.second].map((v) => v.toString().padLeft(2, '0')).join(':');

/// A one-trip GTFS: trip t1 on route 10 calling at S1 (sequence 2) and S2 (sequence 3).
TripSchedule _schedule(Map<int, (String, DateTime)> stops) {
  final repo = GtfsRepository()
    ..routesById['10'] = const RouteInfo(routeId: '10', routeShortName: '10', routeLongName: 'Ten')
    ..tripsById['t1'] = const TripInfo(
      tripId: 't1',
      routeId: '10',
      serviceId: 'daily',
      tripHeadsign: 'MUN',
      directionId: 0,
    );
  stops.forEach((seq, s) {
    final (stop, at) = s;
    repo.stopsById[stop] = StopInfo(stopId: stop, stopName: 'Stop $stop', stopLat: 0, stopLon: 0);
    repo.stopTimesByStopId[stop] = [
      StopTimeRow(tripId: 't1', arrivalTime: _clock(at), departureTime: _clock(at), stopId: stop, stopSequence: seq),
    ];
  });
  return TripSchedule(repo, {'t1'});
}

/// Polls every 10 s from [start] to [end], the trip's listing given by [stopsAt].
Stream<String> _polls(
  DateTime start,
  DateTime end,
  List<(int, String, DateTime)>? Function(DateTime) stopsAt, {
  int Function(DateTime t, int seq)? delayAt,
}) async* {
  for (var t = start; !t.isAfter(end); t = t.add(const Duration(seconds: 10))) {
    yield _pollLine(t, trip: 't1', stops: stopsAt(t), delayOf: delayAt == null ? null : (seq) => delayAt(t, seq));
  }
}

AlertRecord _rec(ReplaySummary s, String stop, int lead) =>
    s.records.singleWhere((r) => r.stopId == stop && r.lead == lead);

// ── Tests ───────────────────────────────────────────────────────────────────────────────────────────────────────────

/// The capture and its GTFS, loaded once for the capture tests.
typedef _Capture = ({List<ReplayPoll> polls, Map<String, List<Fix>> fixes, TripSchedule schedule, int trips});
Future<_Capture>? _loaded;

Future<_Capture> _capture(String path, String gtfsDir) => _loaded ??= () async {
  final fixes = <String, List<Fix>>{};
  final polls = await loadCapture(
    File(path).openRead().transform(utf8.decoder).transform(const LineSplitter()),
    fixes: fixes,
  );
  final repo = GtfsRepository();
  await repo.loadFromDirectory(gtfsDir);
  final tripIds = {for (final p in polls) ...?p.trips?.keys};
  return (polls: polls, fixes: fixes, schedule: TripSchedule(repo, tripIds), trips: tripIds.length);
}();

void main() {
  final capturePath = Platform.environment['ALERT_CAPTURE'];
  final gtfsDir = Platform.environment['ALERT_GTFS'];
  final captureSkip = capturePath == null || gtfsDir == null
      ? 'set ALERT_CAPTURE (a capture from tool/capture_gtfsrt_alerts.dart) and ALERT_GTFS (a GTFS directory)'
      : false;

  test(
    'replayed GTFS-RT alerts: ≥ 70% within ±2 min of the GPS passage − lead, ≤ 20% over 2 min late (spec §1)',
    () async {
      final (:polls, :fixes, :schedule, :trips) = await _capture(capturePath!, gtfsDir!);
      expect(polls, isNotEmpty);
      expect(
        polls.first.at.timeZoneOffset,
        const Duration(hours: -2, minutes: -30),
        reason: 'GTFS times are St. John\'s wall clock: run with TZ=America/St_Johns',
      );

      // For reference only: the stop-drop-off truth (the stop leaving the trip's predictions).
      final dropOff = replayAlerts(polls, schedule);

      // The clock is right: a live prediction lands near its timetable time, not 2.5 h off.
      final first = dropOff.records.first;
      expect(
        first.expectedAt.difference(first.scheduledAt).abs(),
        lessThanOrEqualTo(const Duration(minutes: 30)),
        reason:
            'trip ${first.trip} stop ${first.stopId}: predicted ${first.expectedAt}, scheduled ${first.scheduledAt}',
      );

      final date = polls.first.at.toIso8601String().substring(0, 10);
      final csv = File('build/alert_replay_$date.csv');
      csv.parent.createSync(recursive: true);
      csv.writeAsStringSync('${dropOff.csv()}\n');

      // The criterion: the production path, scored against the bus's GPS passage.
      final setups = setupAlerts(polls, schedule).where((s) => !s.tooLate).toList();
      final gps = gpsTruths(setups, schedule, fixes);
      final fired = {for (final s in gps.at.keys) s: runAlert(s, polls, production)};
      Trial trial(AlertSetup s) => Trial(s, fired[s]?.difference(gps.at[s]!.subtract(Duration(minutes: s.lead))));
      final trialsAll = [for (final s in gps.at.keys) trial(s)];
      final score = GpsScore(trialsAll);
      String hms(DateTime? t) => t == null ? '-' : t.toIso8601String().substring(11, 19);
      final worst = [...trialsAll]
        ..sort((a, b) => (b.error?.inSeconds.abs() ?? 1 << 30).compareTo(a.error?.inSeconds.abs() ?? 1 << 30));

      // ignore: avoid_print
      print(
        'polls ${polls.length} (${polls.where((p) => p.replayed).length} replayed), '
        '${polls.first.at} .. ${polls.last.at}; trips in trip updates $trips; CSV ${csv.path}\n'
        '${setups.length} alerts set; GPS truth ${gps.at.length}, no GPS fix within 60 m ${gps.noFix}, '
        'bus passed before the alert was set ${gps.passedBefore}\n'
        'production against the GPS passage (spec §1): ${score.format()}\n'
        '${[
          for (final lead in alertLeadChoices) '  lead $lead min: ${GpsScore([for (final t in trialsAll)
              if (t.setup.lead == lead) t]).format()}',
        ].join('\n')}\n'
        '$accuracyHeader\n'
        '${accuracyRow('production', trialsAll)}\n'
        '${[
          for (final lead in alertLeadChoices) accuracyRow('  lead $lead', [for (final t in trialsAll)
              if (t.setup.lead == lead) t]),
        ].join('\n')}\n'
        'worst 10 against the GPS passage (unfired first):\n'
        '${worst.take(10).map((t) {
          final s = t.setup;
          return '  trip ${s.trip} rt ${s.route} stop ${s.stopId} (seq ${s.seq}) lead ${s.lead}: set ${hms(s.setAt)}, '
              'predicted at set ${hms(s.alert.expectedAt)}, GPS ${hms(gps.at[s])}, drop-off ${hms(dropOffTruth(s))}, '
              'fired ${hms(fired[s])}, error ${t.error?.inSeconds ?? 'unfired'} s';
        }).join('\n')}\n'
        'for reference, against the stop drop-off (±60 s):\n'
        '${dropOff.format()}',
      );

      expect(score.attempted, greaterThanOrEqualTo(50), reason: 'too few alerts for the score to mean anything');
      expect(score.withinShare, greaterThanOrEqualTo(0.7), reason: score.format());
      expect(score.lateShare, lessThanOrEqualTo(0.2), reason: score.format());
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: captureSkip,
  );

  test(
    'alert accuracy experiment: prediction and firing variants against the GPS passage (no criterion asserted)',
    () async {
      final (:polls, :fixes, :schedule, trips: _) = await _capture(capturePath!, gtfsDir!);
      final report = accuracyExperiment(polls, schedule, fixes);
      // ignore: avoid_print
      print(report);
      expect(report, contains('GPS passage'));
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: captureSkip,
  );

  group('synthetic GTFS-RT', () {
    final start = DateTime(2026, 10, 6, 8, 0, 0);
    DateTime at(int m, [int s = 0]) => start.add(Duration(minutes: m, seconds: s));
    // S1 at 08:05 and S2 at 08:06, 3 min late: the app predicts 08:08 and 08:09.
    final s1 = (2, 'S1', at(5)), s2 = (3, 'S2', at(6));
    final schedule = _schedule({2: ('S1', at(5)), 3: ('S2', at(6))});

    test('the stop leaving the predictions is the departure: leads 3 and 5 fire on time, 10 is too late', () async {
      final polls = await loadCapture(
        _polls(start, at(12), (t) {
          if (t.isBefore(at(8))) return [s1, s2];
          if (t.isBefore(at(9))) return [s2];
          return null; // the trip ends at S2, due now
        }),
      );
      final summary = replayAlerts(polls, schedule);

      for (final stop in ['S1', 'S2']) {
        expect(_rec(summary, stop, 10).outcome, Outcome.setTooLate, reason: '$stop is under 12 min away');
        for (final lead in [3, 5]) {
          final r = _rec(summary, stop, lead);
          expect(r.outcome, Outcome.fired, reason: '$stop lead $lead');
          expect(r.error!.inSeconds.abs(), lessThanOrEqualTo(60), reason: '$stop lead $lead: ${r.error}');
        }
      }
      expect(_rec(summary, 'S1', 3).expectedAt, at(8));
      expect(_rec(summary, 'S1', 3).departure, at(8), reason: 'the poll where S1 left the trip\'s list');
      expect(_rec(summary, 'S2', 3).departure, at(9), reason: 'the trip vanished with S2 due');
      expect(summary.count(Outcome.unfired), 0);
      expect(summary.attempted(), 4);
      expect(summary.withinShare(), 1.0);
    });

    test('a trip that vanishes 3 min before the stop departs at the vanish poll', () async {
      final polls = await loadCapture(_polls(start, at(12), (t) => t.isBefore(at(5)) ? [s1] : null));
      final summary = replayAlerts(polls, schedule);

      for (final lead in [3, 5]) {
        final r = _rec(summary, 'S1', lead);
        expect(r.outcome, Outcome.fired, reason: 'lead $lead');
        expect(r.departure, at(5));
        // The bus was still predicted for 08:08, so the alert keeps that time: it fires at 08:08 − lead − the 1 min
        // margin, 2 min after the real target.
        expect(r.firedAt, at(7 - lead));
        expect(r.error, const Duration(minutes: 2));
      }
      expect(_rec(summary, 'S1', 10).outcome, Outcome.setTooLate);
      expect(summary.count(Outcome.unfired), 0);
    });

    test('a trip that vanishes while the stop is over 5 min ahead is a ghost, and a dropout is not a vanish', () async {
      final ghost = replayAlerts(
        await loadCapture(_polls(start, at(12), (t) => t.isBefore(at(2)) ? [s1] : null)),
        schedule,
      );
      expect(_rec(ghost, 'S1', 3).outcome, Outcome.ghost);
      expect(_rec(ghost, 'S1', 5).outcome, Outcome.ghost);
      expect(ghost.attempted(), 0);

      // Missing for 30 s at 08:02 and back with S1 listed: still running, departs when S1 leaves at 08:08.
      final dropout = replayAlerts(
        await loadCapture(
          _polls(start, at(12), (t) {
            if (!t.isBefore(at(2)) && t.isBefore(at(2, 30))) return null;
            return t.isBefore(at(8)) ? [s1, s2] : [s2];
          }),
        ),
        schedule,
      );
      expect(_rec(dropout, 'S1', 3).departure, at(8));
      expect(_rec(dropout, 'S1', 3).outcome, Outcome.fired);
      expect(_rec(dropout, 'S2', 3).outcome, Outcome.captureEnded, reason: 'S2 still listed at the end');
    });

    test(
      'polls are replayed at the watcher\'s 30 s: every 3rd of a 10 s capture, every one of a 30 s capture',
      () async {
        final tenSeconds = await loadCapture(_polls(start, at(2), (_) => [s1]));
        expect(
          [
            for (final (i, p) in tenSeconds.indexed)
              if (p.replayed) i,
          ],
          [0, 3, 6, 9, 12],
        );
        final thirtySeconds = await loadCapture(
          Stream.fromIterable([
            for (var i = 0; i < 4; i++) _pollLine(at(0, 30 * i), trip: 't1', stops: [s1]),
          ]),
        );
        expect(thirtySeconds.every((p) => p.replayed), isTrue);
      },
    );

    test('a one-poll dip in the bus\'s delay fires the schedule difference early; confirming twice or the stop\'s own '
        'time (production) does not', () async {
      // At 08:01 the feed says the bus is 5 min early at S1, its first listed stop, but keeps S2 at 08:09.
      final polls = await loadCapture(
        _polls(
          start,
          at(12),
          (t) => t.isBefore(at(8)) ? [s1, s2] : (t.isBefore(at(9)) ? [s2] : null),
          delayAt: (t, seq) => seq == 2 && !t.isBefore(at(1)) && t.isBefore(at(1, 30)) ? -300 : 180,
        ),
      );
      final s2lead3 = setupAlerts(polls, schedule).singleWhere((s) => s.stopId == 'S2' && s.lead == 3);
      final fired = {for (final v in variants) v.name: runAlert(s2lead3, polls, v)};
      expect(runAlert(s2lead3, polls, production), at(5), reason: 'S2\'s own time, 08:09, − 3 − the 1 min margin');
      expect(fired['A schedule diff'], at(1), reason: 'S2 predicted at 08:01 for one poll');
      expect(fired['B confirm twice'], at(6, 30), reason: 'the dip lasted one poll; 08:06 confirmed at 08:06:30');
      expect(fired['C per-stop time'], at(6), reason: 'S2\'s own time stayed 08:09');
      expect(fired['D B+C'], at(6, 30));
      expect(fired['E C, median of 3'], at(6));
      expect(fired['F production (C − 60 s)'], at(5));
      expect(fired['G A − 60 s (iPhone)'], at(1));
    });

    test('the GPS passage is the first visit\'s closest point to the stop, between fixes', () {
      const lat = 47.5, lon = -52.7;
      final perMetre = 1 / (111320 * math.cos(lat * math.pi / 180));
      final t0 = DateTime(2026, 10, 6, 8);
      final s0 = t0.millisecondsSinceEpoch ~/ 1000;
      Fix f(int dt, double metresEast) => Fix(s0 + dt, lat, lon + metresEast * perMetre);
      // Westward 200 m, 40 m, then 40 m and 200 m east: it passes the stop halfway between the 2nd and 3rd fixes.
      final fixes = [f(0, -200), f(10, -40), f(20, 40), f(30, 200)];
      expect(
        gpsPassage(fixes, lat, lon, t0)!.difference(t0.add(const Duration(seconds: 15))).inMilliseconds.abs(),
        lessThan(200),
      );
      expect(gpsPassage([f(0, -200), f(10, -80), f(20, 80)], lat, lon, t0), isNull, reason: 'never within 60 m');
      expect(gpsPassage(fixes, lat, lon, t0.add(const Duration(minutes: 6))), isNull, reason: 'before the window');
      // Out and back past the stop: the last visit before the stop left the feed, else the first.
      final twice = [...fixes, f(300, 200), f(310, 40), f(320, -40), f(330, -200)];
      final second = t0.add(const Duration(seconds: 315));
      expect(
        gpsPassage(twice, lat, lon, t0, until: t0.add(const Duration(minutes: 8)))!.difference(second).inSeconds,
        0,
      );
      expect(gpsPassage(twice, lat, lon, t0)!.difference(t0.add(const Duration(seconds: 15))).inSeconds, 0);
      expect(
        gpsPassage(twice, lat, lon, t0, until: t0.subtract(const Duration(minutes: 2))),
        isNull,
        reason: 'no visit before the drop-off',
      );
    });

    test('the §1 score: ±2 min inclusive, over 2 min late, an unfired alert fails', () {
      // The score reads only the errors; every trial shares one alert.
      AlertSetup any() => AlertSetup(
        alert: ArrivalAlert(
          stopId: 'S1',
          stopName: 'Stop S1',
          routeShortName: '10',
          headsign: 'MUN',
          tripId: 't1',
          scheduledAt: at(5),
          expectedAt: at(5),
          live: true,
          leadMinutes: 3,
          setAt: start,
        ),
        route: '10',
        seq: 2,
        setIndex: 0,
        dropOff: (kind: DepartureKind.captureEnded, at: null),
        tooLate: false,
      );
      Trial t(int? seconds) => Trial(any(), seconds == null ? null : Duration(seconds: seconds));
      final score = GpsScore([t(0), t(120), t(-120), t(121), t(-121), t(null), t(30), t(-30), t(60), t(90)]);
      expect(score.attempted, 10);
      expect(score.unfired, 1);
      expect(score.within, 7);
      expect(score.late, 1);
      expect(score.withinShare, 0.7);
      expect(score.lateShare, 0.1);
      expect(score.meetsCriterion, isFalse, reason: 'fewer than 50 scored');
      expect(GpsScore([for (var i = 0; i < 5; i++) ...score.trials]).meetsCriterion, isTrue);
      expect(
        GpsScore([for (var i = 0; i < 5; i++) ...score.trials, t(200), t(200)]).meetsCriterion,
        isFalse,
        reason: 'under 70% within',
      );
    });

    test('capture time is read as the local clock', () {
      final t = DateTime(2026, 10, 5, 9, 34, 23, 126);
      expect(pollTimeOf(t.toUtc().toIso8601String()), t);
      expect(pollTimeOf(t.toUtc().toIso8601String()).isUtc, isFalse);
    });
  });
}

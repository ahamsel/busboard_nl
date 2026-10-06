// test/arrival_alerts/alert_replay_test.dart
//
// Replays recorded GTFS-RT through the Android watcher's path (spec §5) and scores the alerts against spec §1:
// within ±1 min of "real departure − lead" in at least 90% of cases, never more than 3 min late, and an alert that
// never fires is a failure. Record a capture with tool/capture_gtfsrt_alerts.dart, then:
//
//   ALERT_CAPTURE=test/fixtures/timetrack/raw_gtfsrt_2026-10-05.jsonl ALERT_GTFS=build/gtfs_current \
//     flutter test test/arrival_alerts/alert_replay_test.dart
//
// GTFS service-day times are St. John's wall-clock times, and the app reads the feed's timestamps in the phone's
// local zone, so the capture test runs in America/St_Johns (the machine's zone, or `TZ=America/St_Johns`).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
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
  TripListing(this.seqs, this.stopIds, this.times);

  final Int32List seqs;
  final List<String> stopIds;

  /// The feed's predicted time at each stop, in epoch seconds (0 when the feed gave none).
  final Int64List times;

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

/// Reads a capture's JSON lines one at a time and replays one poll per [watcherCadence] through the production fetch:
/// every 3rd poll of a 10 s capture, every poll of a 30 s one (tool/capture_gtfsrt_alerts.dart).
Future<List<ReplayPoll>> loadCapture(Stream<String> lines) async {
  final pool = <String, String>{}; // one copy of each stop id across ~1.7 M listings
  final polls = <ReplayPoll>[];
  DateTime? lastReplayed;
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    final at = pollTimeOf(j['fetch_time'] as String);
    final positions = _feedOf(j['vehicle_positions']);
    final updates = _feedOf(j['trip_updates']);

    Map<String, TripListing>? trips;
    if (updates != null) {
      trips = {};
      for (final e in updates.entity) {
        if (!e.hasTripUpdate() || e.tripUpdate.trip.tripId.isEmpty) continue;
        final stops = e.tripUpdate.stopTimeUpdate;
        final seqs = Int32List(stops.length), times = Int64List(stops.length);
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
        }
        trips[e.tripUpdate.trip.tripId] = TripListing(seqs, ids, times);
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

/// Sets and runs alerts for every trip in [polls] and scores them (spec §1).
ReplaySummary replayAlerts(List<ReplayPoll> polls, TripSchedule schedule) {
  const tracker = AlertTracker();
  final records = <AlertRecord>[];
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
        final departure = departureOf(polls, i, trip, seq);
        for (final lead in alertLeadChoices) {
          AlertRecord record(Outcome o, {DateTime? firedAt}) => AlertRecord(
            trip: trip,
            route: schedule.routeOf(trip),
            stopId: listing.stopIds[k],
            seq: seq,
            lead: lead,
            setAt: now,
            scheduledAt: scheduled[k]!,
            expectedAt: p,
            outcome: o,
            departure: departure.at,
            firedAt: firedAt,
          );
          if (p.difference(now) < Duration(minutes: lead + 1)) {
            records.add(record(Outcome.setTooLate));
            continue;
          }
          if (departure.kind == DepartureKind.ghost) {
            records.add(record(Outcome.ghost));
            continue;
          }
          if (departure.kind == DepartureKind.captureEnded) {
            records.add(record(Outcome.captureEnded));
            continue;
          }

          var alert = alertFor(k, lead, scheduled[k]!, p, vehicle);
          DateTime? firedAt;
          for (var j = i; j < polls.length; j++) {
            final q = polls[j];
            if (!q.replayed) continue;
            final s = tracker.step(alert, liveResultForAlert(alert, q.feed, q.at), q.at);
            alert = s.alert;
            if (s.fire) {
              firedAt = q.at;
              break;
            }
            if (s.finished) break;
          }
          final target = departure.at!.subtract(Duration(minutes: lead));
          records.add(
            firedAt != null
                ? record(Outcome.fired, firedAt: firedAt)
                : record(target.isAfter(polls.last.at) ? Outcome.captureEnded : Outcome.unfired),
          );
        }
      }
    });
  }
  return ReplaySummary(records);
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
String _pollLine(DateTime at, {required String trip, required List<(int, String, DateTime)>? stops, int delay = 180}) {
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
                'arrival': {'delay': delay, 'time': '${_epoch(scheduled) + delay}'},
                'departure': {'delay': delay, 'time': '${_epoch(scheduled) + delay}'},
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
Stream<String> _polls(DateTime start, DateTime end, List<(int, String, DateTime)>? Function(DateTime) stopsAt) async* {
  for (var t = start; !t.isAfter(end); t = t.add(const Duration(seconds: 10))) {
    yield _pollLine(t, trip: 't1', stops: stopsAt(t));
  }
}

AlertRecord _rec(ReplaySummary s, String stop, int lead) =>
    s.records.singleWhere((r) => r.stopId == stop && r.lead == lead);

// ── Tests ───────────────────────────────────────────────────────────────────────────────────────────────────────────

void main() {
  final capturePath = Platform.environment['ALERT_CAPTURE'];
  final gtfsDir = Platform.environment['ALERT_GTFS'];

  test(
    'replayed GTFS-RT alerts fire within ±1 min of real departure − lead (spec §1)',
    () async {
      final polls = await loadCapture(
        File(capturePath!).openRead().transform(utf8.decoder).transform(const LineSplitter()),
      );
      expect(polls, isNotEmpty);
      expect(
        polls.first.at.timeZoneOffset,
        const Duration(hours: -2, minutes: -30),
        reason: 'GTFS times are St. John\'s wall clock: run with TZ=America/St_Johns',
      );

      final repo = GtfsRepository();
      await repo.loadFromDirectory(gtfsDir!);
      final tripIds = {for (final p in polls) ...?p.trips?.keys};
      final summary = replayAlerts(polls, TripSchedule(repo, tripIds));

      // The clock is right: a live prediction lands near its timetable time, not 2.5 h off.
      final first = summary.records.first;
      expect(
        first.expectedAt.difference(first.scheduledAt).abs(),
        lessThanOrEqualTo(const Duration(minutes: 30)),
        reason:
            'trip ${first.trip} stop ${first.stopId}: predicted ${first.expectedAt}, scheduled ${first.scheduledAt}',
      );

      final date = polls.first.at.toIso8601String().substring(0, 10);
      final csv = File('build/alert_replay_$date.csv');
      csv.parent.createSync(recursive: true);
      csv.writeAsStringSync('${summary.csv()}\n');

      // ignore: avoid_print
      print(
        'polls ${polls.length} (${polls.where((p) => p.replayed).length} replayed), '
        '${polls.first.at} .. ${polls.last.at}; trips in trip updates ${tripIds.length}; CSV ${csv.path}\n'
        '${summary.format()}\n'
        'worst 10 by |error| (unfired first):\n'
        '${summary.worst(10).map((r) => '  trip ${r.trip} rt ${r.route} stop ${r.stopId} (seq ${r.seq}) lead ${r.lead}: '
            'set ${r.setAt}, expected ${r.expectedAt}, departure ${r.departure}, target ${r.target}, '
            'fired ${r.firedAt ?? '-'}, error ${r.error?.inSeconds ?? '-'} s, ${r.outcome.name}').join('\n')}',
      );

      expect(summary.attempted(), greaterThanOrEqualTo(50), reason: 'too few alerts for the score to mean anything');
      expect(summary.withinShare(), greaterThanOrEqualTo(0.9));
      expect(summary.worstLate() ?? 0, lessThanOrEqualTo(180));
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: capturePath == null || gtfsDir == null
        ? 'set ALERT_CAPTURE (a capture from tool/capture_gtfsrt_alerts.dart) and ALERT_GTFS (a GTFS directory)'
        : false,
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
        expect(_rec(summary, stop, 10).outcome, Outcome.setTooLate, reason: '$stop is under 11 min away');
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
        // The bus was still predicted for 08:08, so the alert keeps that time: 3 min after the real target.
        expect(r.firedAt, at(8 - lead));
        expect(r.error, const Duration(minutes: 3));
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

    test('capture time is read as the local clock', () {
      final t = DateTime(2026, 10, 5, 9, 34, 23, 126);
      expect(pollTimeOf(t.toUtc().toIso8601String()), t);
      expect(pollTimeOf(t.toUtc().toIso8601String()).isUtc, isFalse);
    });
  });
}

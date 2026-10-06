import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_tracker.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/domain/arrival_alerts/gtfs_rt_source.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 10, 6, 8, 0);

ArrivalAlert _alert({DateTime? scheduled, DateTime? setAt}) {
  final at = scheduled ?? DateTime(2026, 10, 6, 8, 12);
  return ArrivalAlert(
    stopId: '1150',
    stopName: 'MUN Centre',
    routeShortName: '10',
    headsign: 'MUN-CNA-MI',
    tripId: 't1',
    scheduledAt: at,
    expectedAt: at,
    live: true,
    leadMinutes: 5,
    setAt: setAt ?? t0,
    lastSeenAt: setAt ?? t0,
  );
}

/// A GTFS-RT vehicle as `TimeTrackApi` builds it: [diff] positive is ahead; null is "no delay data".
TimeTrackVehicle _vehicle({String trip = 't1', String id = '1415', int? diff = -6, required DateTime fix}) =>
    TimeTrackVehicle(
      routeRun: 'Rt 10',
      currentRoute: '10',
      routeNumber: 10,
      vehicle: id,
      timeStamp: fix.toIso8601String(),
      deviation: diff == null ? '' : '${-diff} MINS BEHIND',
      currentLocation: '',
      busLat: 47.57,
      busLon: -52.73,
      heading: '',
      speed: 0,
      positionTime: fix.toIso8601String(),
      positionTimeSeconds: fix.hour * 3600 + fix.minute * 60 + fix.second,
      gtfsTripHeadsign: '',
      gtfsServiceId: '',
      gtfsStopSequenceStatus: diff == null ? '' : 'BEHIND',
      gtfsStopSequenceMinsFromStop: 0,
      gtfsStopSequenceDeviation: diff == null ? '' : '${-diff} MINS BEHIND',
      gtfsStopSequenceClosestStop: '',
      gtfsStopSequenceSchedDifferenceMins: diff ?? 0,
      gtfsTripId: trip,
      shortStatus: diff == null ? '' : 'B${-diff}',
      departureTimeAtClosestStop: 0,
    );

TimeTrackFetchResult _feed(List<TimeTrackVehicle> v, {Map<String, Map<String, List<FeedStopTime>>>? stopTimes}) =>
    TimeTrackFetchResult.success(v, source: LiveDataSource.gtfsRealtime, stopTimes: stopTimes ?? const {});

/// The feed's own time at [h]:[m]:[s] on 2026-10-06, with its delay.
FeedStopTime _at(int h, int m, {int s = 0, int? delayMins}) => FeedStopTime(
      time: DateTime(2026, 10, 6, h, m, s),
      delay: delayMins == null ? null : Duration(minutes: delayMins),
    );

int _secs(int h, int m, [int s = 0]) => h * 3600 + m * 60 + s;

void main() {
  final now = t0.add(const Duration(minutes: 1));
  const tracker = AlertTracker();

  test('a fresh vehicle on the trip, 6 min behind: one realtime row, predicted = scheduled + 6 min', () {
    final r = liveResultForAlert(_alert(), _feed([_vehicle(fix: now.subtract(const Duration(seconds: 20)))]), now);
    expect(r.succeeded, isTrue);
    final d = r.departures.single;
    expect(d.tripId, 't1');
    expect(d.routeShortName, '10');
    expect(d.routeRun, '');
    expect(d.vehicle, '1415');
    expect(d.isRealtime, isTrue);
    expect(d.scheduledDepartureSeconds, 8 * 3600 + 12 * 60);
    expect(d.predictedDepartureSeconds, 8 * 3600 + 18 * 60);
    final s = tracker.step(_alert(), r, now);
    expect(s.source, AlertSource.live);
    expect(s.alert.expectedAt, DateTime(2026, 10, 6, 8, 18));
    expect(s.alert.vehicle, '1415');
  });

  test('a fix older than 5 minutes is a ghost: no row', () {
    final r = liveResultForAlert(_alert(), _feed([_vehicle(fix: now.subtract(const Duration(minutes: 5, seconds: 1)))]), now);
    expect(r.succeeded, isTrue);
    expect(r.departures, isEmpty);
  });

  test('a ghost and the real bus on one trip: the fresh one wins', () {
    final r = liveResultForAlert(
      _alert(),
      _feed([
        _vehicle(id: '9999', diff: -20, fix: now.subtract(const Duration(minutes: 30))),
        _vehicle(fix: now.subtract(const Duration(seconds: 10))),
      ]),
      now,
    );
    expect(r.departures.single.vehicle, '1415');
  });

  test('no vehicle on the trip: no row', () {
    final r = liveResultForAlert(_alert(), _feed([_vehicle(trip: 't2', fix: now)]), now);
    expect(r.succeeded, isTrue);
    expect(r.departures, isEmpty);
  });

  test('a failed or missing feed is a failed result', () {
    expect(liveResultForAlert(_alert(), const TimeTrackFetchResult.failure(error: 'HTTP 503'), now).succeeded, isFalse);
    expect(liveResultForAlert(_alert(), null, now).succeeded, isFalse);
  });

  test('the tracker honours succeeded == false, even with a matching row in it', () {
    final row = liveResultForAlert(_alert(), _feed([_vehicle(fix: now)]), now).departures.single;
    final failed = MetrobusDeparturesResult(
      departures: [row],
      succeeded: false,
      realtimeAvailable: false,
      serviceOperating: true,
      fetchedAt: now,
    );
    final s = tracker.step(_alert(), failed, t0.add(const Duration(minutes: 3)));
    expect(s.source, AlertSource.lost);
  });

  test('a vehicle without schedule-difference data does not count as live', () {
    final r = liveResultForAlert(_alert(), _feed([_vehicle(diff: null, fix: now)]), now);
    expect(r.departures, isEmpty);
  });

  group('the feed\'s own time at the alert\'s stop', () {
    // The vehicle says 6 min behind (08:18); the trip update has its own time for each stop.
    TimeTrackVehicle fresh() => _vehicle(fix: now.subtract(const Duration(seconds: 20)));

    test('a per-stop time for the alert\'s stop is the prediction', () {
      final feed = _feed([fresh()], stopTimes: {
        't1': {
          '1100': [_at(8, 5, delayMins: 1)],
          '1150': [_at(8, 16, s: 30, delayMins: 4)],
        },
      });
      final d = liveResultForAlert(_alert(), feed, now).departures.single;
      expect(d.scheduledDepartureSeconds, _secs(8, 12));
      expect(d.predictedDepartureSeconds, _secs(8, 16, 30));
      expect(tracker.step(_alert(), liveResultForAlert(_alert(), feed, now), now).alert.expectedAt,
          DateTime(2026, 10, 6, 8, 16, 30));
    });

    test('no update for the stop falls back to scheduled − schedule difference', () {
      final feed = _feed([fresh()], stopTimes: {
        't1': {'1100': [_at(8, 5, delayMins: 1)]},
        't2': {'1150': [_at(8, 30, delayMins: 0)]},
      });
      expect(liveResultForAlert(_alert(), feed, now).departures.single.predictedDepartureSeconds, _secs(8, 18));
    });

    test('a stop listed twice uses the visit nearest the alert\'s scheduled time', () {
      final feed = _feed([fresh()], stopTimes: {
        't1': {
          // Scheduled 08:45 (47 − 2) and 08:12 (15 − 3): the second is the alert's visit.
          '1150': [_at(8, 47, delayMins: 2), _at(8, 15, delayMins: 3)],
        },
      });
      expect(liveResultForAlert(_alert(), feed, now).departures.single.predictedDepartureSeconds, _secs(8, 15));
    });

    test('a delay and no time: scheduled + delay', () {
      final feed = _feed([fresh()], stopTimes: {
        't1': {'1150': [const FeedStopTime(delay: Duration(minutes: 4))]},
      });
      expect(liveResultForAlert(_alert(), feed, now).departures.single.predictedDepartureSeconds, _secs(8, 16));
    });

    test('an update with neither time nor delay falls back', () {
      final feed = _feed([fresh()], stopTimes: {
        't1': {'1150': [const FeedStopTime()]},
      });
      expect(liveResultForAlert(_alert(), feed, now).departures.single.predictedDepartureSeconds, _secs(8, 18));
    });

    test('a stale fix or a vehicle with no delay data is still not live, whatever the stop\'s time', () {
      final stopTimes = {
        't1': {'1150': [_at(8, 16, delayMins: 4)]},
      };
      final stale = _vehicle(fix: now.subtract(const Duration(minutes: 5, seconds: 1)));
      expect(liveResultForAlert(_alert(), _feed([stale], stopTimes: stopTimes), now).departures, isEmpty);
      final noDelay = _vehicle(diff: null, fix: now);
      expect(liveResultForAlert(_alert(), _feed([noDelay], stopTimes: stopTimes), now).departures, isEmpty);
      expect(liveResultForAlert(_alert(), _feed([], stopTimes: stopTimes), now).departures, isEmpty,
          reason: 'a trip update without a vehicle is not live');
    });

    test('after midnight the stop\'s time counts past 24:00, as the schedule does', () {
      final late = DateTime(2026, 10, 6, 23, 55);
      final a = _alert(scheduled: DateTime(2026, 10, 7, 0, 10), setAt: DateTime(2026, 10, 6, 23, 50));
      final feed = _feed([_vehicle(diff: -3, fix: late)], stopTimes: {
        't1': {'1150': [FeedStopTime(time: DateTime(2026, 10, 7, 0, 14), delay: const Duration(minutes: 4))]},
      });
      final d = liveResultForAlert(a, feed, late).departures.single;
      expect(d.scheduledDepartureSeconds, _secs(24, 10));
      expect(d.predictedDepartureSeconds, _secs(24, 14));
      expect(tracker.step(a, liveResultForAlert(a, feed, late), late).alert.expectedAt, DateTime(2026, 10, 7, 0, 14));
    });
  });

  test('a trip after midnight maps to tomorrow', () {
    final late = DateTime(2026, 10, 6, 23, 55);
    final a = _alert(scheduled: DateTime(2026, 10, 7, 0, 10), setAt: DateTime(2026, 10, 6, 23, 50));
    final r = liveResultForAlert(a, _feed([_vehicle(diff: -3, fix: late)]), late);
    final d = r.departures.single;
    expect(d.scheduledDepartureSeconds, 24 * 3600 + 10 * 60);
    expect(d.predictedDepartureSeconds, 24 * 3600 + 13 * 60);
    expect(tracker.step(a, r, late).alert.expectedAt, DateTime(2026, 10, 7, 0, 13));
  });

  test('just after midnight, a trip from before midnight stays yesterday', () {
    final justAfter = DateTime(2026, 10, 7, 0, 2);
    final a = _alert(scheduled: DateTime(2026, 10, 6, 23, 58), setAt: DateTime(2026, 10, 6, 23, 40));
    final r = liveResultForAlert(a, _feed([_vehicle(diff: -6, fix: justAfter)]), justAfter);
    expect(tracker.step(a, r, justAfter).alert.expectedAt, DateTime(2026, 10, 7, 0, 4));
  });
}

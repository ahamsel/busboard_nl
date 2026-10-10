// test/arrival_alerts/midnight_feed_day_shift_test.dart
//
// Recorded GTFS-RT for route 2 trip 261767, last night's (2026-10-09 service) 23:xx → 24:25 run, at 23:59:16 and
// 00:01:16 NDT. Before midnight the trip update's times are right; from midnight on, every time is dated a day late
// (exactly +24 h), so stop 1490's 24:00:00 (2026-10-10 00:00) reads as 2026-10-11 00:00 less its delay.
import 'dart:convert';
import 'dart:io';

import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/domain/arrival_alerts/gtfs_rt_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _fixture = 'test/fixtures/gtfsrt_midnight_2026-10-10/route2_trip_261767.jsonl';
const _trip = '261767';

/// An epoch second as an instant (comparisons are by instant, so the test doesn't depend on the machine's zone).
Matcher _epoch(int s) {
  final at = DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
  return predicate<DateTime?>((t) => t != null && t.isAtSameMomentAs(at), 'the instant ${at.toIso8601String()}');
}

/// Stop 1490's timetable time, 24:00:00 on 2026-10-09's service: 2026-10-10 00:00 NDT.
final _stop1490 = DateTime.utc(2026, 10, 10, 2, 30);

/// Stop 1485's timetable time, 23:59:23 on 2026-10-09: before midnight.
final _stop1485 = DateTime.utc(2026, 10, 10, 2, 29, 23);

Future<(TimeTrackFetchResult, DateTime)> _poll(int index) async {
  final poll = jsonDecode(File(_fixture).readAsLinesSync()[index]) as Map<String, dynamic>;
  List<int> bytes(String key) => (FeedMessage()..mergeFromProto3Json(poll[key])).writeToBuffer();
  final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/vehiclepositions')) return http.Response.bytes(bytes('vehicle_positions'), 200);
    if (path.endsWith('/tripupdates')) return http.Response.bytes(bytes('trip_updates'), 200);
    return http.Response('', 404);
  });
  final feed = await TimeTrackApi(client: client).fetchLiveVehiclesResult();
  return (feed, DateTime.parse(poll['fetch_time'] as String));
}

void main() {
  test('before midnight the feed is on the right day', () async {
    final (feed, _) = await _poll(0);
    expect(feedTimeAtStop(feed, _trip, '1490', _stop1490), _epoch(1791599400));
  });

  test("after midnight, last night's trip times a day late still match their stops, on the right day", () async {
    final (feed, now) = await _poll(1);
    expect(feed.stopTimes[_trip]!['1490']!.single.time, _epoch(1791685679), reason: 'the feed: +24 h, 2 min early');
    expect(feedTimeAtStop(feed, _trip, '1490', _stop1490), _epoch(1791599279));
    expect(feedTimeAtStop(feed, _trip, '1485', _stop1485), _epoch(1791685642 - 86400));
    expect(liveTripUsable(feed, _trip, now), isTrue);
  });

  test("the bell's live time for last night's 24:00 stop is 2 minutes early, not blank", () async {
    final (feed, now) = await _poll(1);
    final at = _stop1490.toLocal();
    final alert = ArrivalAlert(
      stopId: '1490',
      stopName: 'Stop 1490',
      routeShortName: '2',
      headsign: 'PLEASANTVILLE - AVALON MALL',
      tripId: _trip,
      scheduledAt: at,
      expectedAt: at,
      live: true,
      leadMinutes: 3,
      setAt: now,
      lastSeenAt: now,
    );
    final row = liveResultForAlert(alert, feed, now).departures.single;
    expect(row.predictedDepartureSeconds! - row.scheduledDepartureSeconds!, -121);
  });
}

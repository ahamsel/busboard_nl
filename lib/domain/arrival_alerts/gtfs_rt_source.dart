import '../../data/gtfs/gtfs_time.dart';
import '../../data/realtime/metrobus_mobile_api.dart';
import '../../data/realtime/timetrack_api.dart';
import '../../data/realtime/timetrack_models.dart';
import 'alert_tracker.dart';
import 'arrival_alert.dart';

/// A vehicle fix older than this is a feed ghost, not a live bus.
const liveFixMaxAge = Duration(minutes: 5);

/// The alert's live departure from the GTFS-RT feeds, in the shape [AlertTracker] reads (spec §3.1, §3.2).
///
/// The time is the trip update's own time at the alert's stop ([TimeTrackFetchResult.stopTimes], matched by stop
/// id; a trip that visits the stop twice uses the visit nearest the alert's scheduled time, and only a visit whose
/// own timetable time is within [AlertTracker.sameRunWindow] of it counts). When the update has no such visit, it
/// falls back to the Board's time: the alert's scheduled time shifted by the vehicle's
/// schedule difference. Either way the trip needs a fresh vehicle with a known delay to count as live. A failed feed
/// is a failed result; a succeeded feed without such a vehicle is a succeeded result with no rows.
MetrobusDeparturesResult liveResultForAlert(ArrivalAlert alert, TimeTrackFetchResult? feed, DateTime now) {
  if (feed == null || !feed.succeeded) return MetrobusDeparturesResult.failure();
  final vehicle = alert.tripId.isEmpty ? null : TimeTrackApi.buildTripIndex(feed.vehicles, now: now)[alert.tripId];
  final rows = vehicle != null && liveTripUsable(feed, alert.tripId, now)
      ? [_departure(alert, vehicle, feedTimeAtStop(feed, alert.tripId, alert.stopId, alert.scheduledAt), now)]
      : const <MetrobusDeparture>[];
  return MetrobusDeparturesResult(
    departures: rows,
    succeeded: true,
    realtimeAvailable: rows.isNotEmpty,
    serviceOperating: true,
    fetchedAt: now,
  );
}

/// The trip's bus counts as live: a fix under [liveFixMaxAge] old and a known delay (also used by the trip planner).
bool liveTripUsable(TimeTrackFetchResult feed, String tripId, DateTime now) {
  if (!feed.succeeded || tripId.isEmpty) return false;
  final v = TimeTrackApi.buildTripIndex(feed.vehicles, now: now)[tripId];
  return v != null && _fresh(v, now) && _delayKnown(v);
}

bool _fresh(TimeTrackVehicle v, DateTime now) {
  final fix = DateTime.tryParse(v.positionTime) ?? DateTime.tryParse(v.timeStamp);
  return fix != null && now.difference(fix) <= liveFixMaxAge;
}

/// The feed reports no delay as 0 with an empty deviation; that is not "on time" (see `BusTrackStore`).
bool _delayKnown(TimeTrackVehicle v) => v.gtfsStopSequenceDeviation.isNotEmpty;

/// The trip update's prediction at the given stop, or null when it lists no visit there with a time or delay
/// within [AlertTracker.sameRunWindow] of the given scheduled time. A loop trip's later visit (once the given one has
/// left the feed) or an absurd feed time is not this visit. A visit dated exactly a day off is this visit on the
/// wrong date: from midnight on, the feed dates last night's still-running trips a day late (every time +24 h,
/// recorded 2026-10-10), so its times come back shifted onto [scheduledAt]'s day.
DateTime? feedTimeAtStop(TimeTrackFetchResult feed, String tripId, String stopId, DateTime scheduledAt) {
  final visits = feed.stopTimes[tripId]?[stopId];
  if (visits == null) return null;
  DateTime? best;
  Duration? bestOff;
  for (final v in visits) {
    final predicted = v.predictedFor(scheduledAt);
    if (predicted == null) continue;
    // A visit's own timetable time is its time less its delay; without both, its prediction stands in.
    final scheduled = v.time != null && v.delay != null ? v.time!.subtract(v.delay!) : predicted;
    final shift = _dayShift(scheduled, scheduledAt);
    final off = scheduled.subtract(shift).difference(scheduledAt).abs();
    if (off > AlertTracker.sameRunWindow) continue;
    if (bestOff == null || off < bestOff) {
      best = predicted.subtract(shift);
      bestOff = off;
    }
  }
  return best;
}

/// The whole day (at most one either way) that [scheduled] sits from [scheduledAt]: zero, or ±24 h.
Duration _dayShift(DateTime scheduled, DateTime scheduledAt) {
  final days = (scheduled.difference(scheduledAt).inSeconds / Duration.secondsPerDay).round().clamp(-1, 1);
  return Duration(days: days);
}

MetrobusDeparture _departure(ArrivalAlert alert, TimeTrackVehicle v, DateTime? atStop, DateTime now) {
  final at = alert.scheduledAt;
  var scheduled = GtfsTime.fromDateTime(at).totalSeconds;
  // A departure after tonight's midnight counts past 24:00, as in GTFS; `instantOfServiceTime` maps it back.
  if (DateTime(at.year, at.month, at.day).isAfter(DateTime(now.year, now.month, now.day))) {
    scheduled += Duration.secondsPerDay;
  }
  // The stop's own time keeps the schedule's service-day counting: scheduled seconds plus its offset. Without one,
  // a positive difference is ahead of schedule: predicted = scheduled − diff (as `ArrivalService`).
  final predicted = atStop != null
      ? scheduled + atStop.difference(at).inSeconds
      : scheduled - v.gtfsStopSequenceSchedDifferenceMins * 60;
  return MetrobusDeparture(
    routeRun: '',
    routeShortName: alert.routeShortName,
    vehicle: v.vehicle,
    scheduledTime: '',
    predictedTime: '',
    headsign: '',
    currentLocation: '',
    isTracked: true,
    tripId: alert.tripId,
    scheduledDepartureSeconds: scheduled,
    predictedDepartureSeconds: predicted,
    isRealtime: true,
  );
}

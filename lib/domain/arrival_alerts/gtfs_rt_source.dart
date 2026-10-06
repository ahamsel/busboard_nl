import '../../data/gtfs/gtfs_time.dart';
import '../../data/realtime/metrobus_mobile_api.dart';
import '../../data/realtime/timetrack_api.dart';
import '../../data/realtime/timetrack_models.dart';
import 'arrival_alert.dart';

/// A vehicle fix older than this is a feed ghost, not a live bus.
const liveFixMaxAge = Duration(minutes: 5);

/// The alert's live departure from the GTFS-RT vehicle feed, in the shape [AlertTracker] reads (spec §3.1).
///
/// The feed has no per-stop predictions, so the time is the Board's: the alert's scheduled time shifted by the
/// vehicle's schedule difference. A failed feed is a failed result; a succeeded feed without a fresh vehicle on the
/// alert's trip, with a known delay, is a succeeded result with no rows.
MetrobusDeparturesResult liveResultForAlert(ArrivalAlert alert, TimeTrackFetchResult? feed, DateTime now) {
  if (feed == null || !feed.succeeded) return MetrobusDeparturesResult.failure();
  final vehicle = alert.tripId.isEmpty ? null : TimeTrackApi.buildTripIndex(feed.vehicles, now: now)[alert.tripId];
  final rows = vehicle != null && _fresh(vehicle, now) && _delayKnown(vehicle)
      ? [_departure(alert, vehicle, now)]
      : const <MetrobusDeparture>[];
  return MetrobusDeparturesResult(
    departures: rows,
    succeeded: true,
    realtimeAvailable: rows.isNotEmpty,
    serviceOperating: true,
    fetchedAt: now,
  );
}

bool _fresh(TimeTrackVehicle v, DateTime now) {
  final fix = DateTime.tryParse(v.positionTime) ?? DateTime.tryParse(v.timeStamp);
  return fix != null && now.difference(fix) <= liveFixMaxAge;
}

/// The feed reports no delay as 0 with an empty deviation; that is not "on time" (see `BusTrackStore`).
bool _delayKnown(TimeTrackVehicle v) => v.gtfsStopSequenceDeviation.isNotEmpty;

MetrobusDeparture _departure(ArrivalAlert alert, TimeTrackVehicle v, DateTime now) {
  final at = alert.scheduledAt;
  var scheduled = GtfsTime.fromDateTime(at).totalSeconds;
  // A departure after tonight's midnight counts past 24:00, as in GTFS; `instantOfServiceTime` maps it back.
  if (DateTime(at.year, at.month, at.day).isAfter(DateTime(now.year, now.month, now.day))) {
    scheduled += Duration.secondsPerDay;
  }
  // A positive difference is ahead of schedule: predicted = scheduled − diff (as `ArrivalService`).
  final predicted = scheduled - v.gtfsStopSequenceSchedDifferenceMins * 60;
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

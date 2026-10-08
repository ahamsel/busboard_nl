import '../../data/realtime/timetrack_api.dart';
import '../arrival_alerts/gtfs_rt_source.dart';
import 'journey.dart';
import 'walking.dart';

/// Ride legs leaving within this of now take live times (spec §3.4).
const liveHorizon = Duration(minutes: 60);

/// [j] with the feed's times on its ride legs that leave within [liveHorizon] of [now] on a usable live trip. An end
/// the feed doesn't list keeps its timetable time; a leg with neither end listed stays as it was.
Journey overlayLive(Journey j, TimeTrackFetchResult feed, DateTime now) {
  final legs = <Leg>[
    for (final leg in j.legs)
      if (leg is RideLeg) _liveRide(j, leg, feed, now) else leg,
  ];
  return j.copyWith(legs: retimeWalks(legs));
}

RideLeg _liveRide(Journey j, RideLeg leg, TimeTrackFetchResult feed, DateTime now) {
  final departsAt = j.at(leg.departs);
  if (departsAt.difference(now) > liveHorizon || !liveTripUsable(feed, leg.tripId, now)) return leg;
  final dep = feedTimeAtStop(feed, leg.tripId, leg.boardStopId, departsAt);
  final arr = feedTimeAtStop(feed, leg.tripId, leg.alightStopId, j.at(leg.arrives));
  if (dep == null && arr == null) return leg;
  return leg.copyWithTimes(
    departs: dep == null ? null : secondsInServiceDay(j.serviceDate, dep),
    arrives: arr == null ? null : secondsInServiceDay(j.serviceDate, arr),
    live: true,
  );
}

/// The first ride that leaves less than [minTransferSeconds] after the bus before it arrives, or before the walk
/// before it ends; null when every connection works.
int? firstTightLeg(Journey j) {
  for (var i = 1; i < j.legs.length; i++) {
    final leg = j.legs[i];
    if (leg is! RideLeg) continue;
    final prev = j.legs[i - 1];
    final needed = prev is RideLeg ? minTransferSeconds : 0;
    if (leg.departs - prev.endSeconds < needed) return i;
  }
  return null;
}

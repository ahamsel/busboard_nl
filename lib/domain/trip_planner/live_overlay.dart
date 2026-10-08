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
  final live = leg.copyWithTimes(
    departs: dep == null ? null : secondsInServiceDay(j.serviceDate, dep),
    arrives: arr == null ? null : secondsInServiceDay(j.serviceDate, arr),
    live: true,
  );
  // One live end against a timetable end can leave the bus arriving before it leaves: not a usable time.
  return live.departs > live.arrives ? leg : live;
}

/// The index of the first ride that can't be taken as shown; null when every one can. A ride is broken when it
/// leaves less than [minTransferSeconds] after the bus before it arrives (or before the walk before it ends), when
/// it arrives before it leaves, or, for the first ride, when the journey starts before [notBefore] (seconds from the
/// service day's midnight).
int? firstTightLeg(Journey j, {int? notBefore}) {
  var firstRide = true;
  for (var i = 0; i < j.legs.length; i++) {
    final leg = j.legs[i];
    if (leg is! RideLeg) continue;
    if (leg.departs > leg.arrives) return i;
    if (firstRide && notBefore != null && j.departs < notBefore) return i;
    firstRide = false;
    if (i == 0) continue;
    final prev = j.legs[i - 1];
    final needed = prev is RideLeg ? minTransferSeconds : 0;
    if (leg.departs - prev.endSeconds < needed) return i;
  }
  return null;
}

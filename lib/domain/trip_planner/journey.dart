/// A step of a planned trip (spec §3.1). Times are seconds from the journey's service-day midnight.
sealed class Leg {
  int get startSeconds;
  int get endSeconds;
}

class WalkLeg extends Leg {
  WalkLeg({required this.fromStopId, required this.toStopId, required this.seconds, required this.startSeconds});

  /// Null at the pin end of the trip.
  final String? fromStopId;
  final String? toStopId;
  final int seconds;
  @override
  final int startSeconds;
  @override
  int get endSeconds => startSeconds + seconds;
}

class RideLeg extends Leg {
  RideLeg({
    required this.routeId,
    required this.tripId,
    required this.boardStopId,
    required this.alightStopId,
    required this.departs,
    required this.arrives,
    required this.stopCount,
    this.live = false,
  });

  final String routeId;
  final String tripId;
  final String boardStopId;
  final String alightStopId;
  final int departs;
  final int arrives;

  /// Stops ridden, counting the one the rider gets off at.
  final int stopCount;

  /// The times came from the live feed (spec §3.4).
  final bool live;

  @override
  int get startSeconds => departs;
  @override
  int get endSeconds => arrives;

  RideLeg copyWithTimes({int? departs, int? arrives, bool? live}) => RideLeg(
        routeId: routeId,
        tripId: tripId,
        boardStopId: boardStopId,
        alightStopId: alightStopId,
        departs: departs ?? this.departs,
        arrives: arrives ?? this.arrives,
        stopCount: stopCount,
        live: live ?? this.live,
      );
}

class Journey {
  Journey({required this.serviceDate, required this.legs, this.replannedForLiveTimes = false});

  /// Date only; leg times count from its midnight.
  final DateTime serviceDate;
  final List<Leg> legs;

  /// A transfer got too tight with live times, and the rest was planned again (spec §3.4).
  final bool replannedForLiveTimes;

  int get departs => legs.first.startSeconds;
  int get arrives => legs.last.endSeconds;
  int get rides => legs.whereType<RideLeg>().length;
  int get walkSeconds => legs.whereType<WalkLeg>().fold(0, (a, w) => a + w.seconds);
  bool get usesLive => legs.whereType<RideLeg>().any((r) => r.live);

  /// The clock time [seconds] after the service day's midnight (wall clock, as GTFS counts it).
  DateTime at(int seconds) => DateTime(serviceDate.year, serviceDate.month, serviceDate.day, 0, 0, seconds);

  Journey copyWith({List<Leg>? legs, bool? replannedForLiveTimes}) => Journey(
        serviceDate: serviceDate,
        legs: legs ?? this.legs,
        replannedForLiveTimes: replannedForLiveTimes ?? this.replannedForLiveTimes,
      );
}

/// A walk between an end of the trip and a stop, in seconds (0 when the end is that stop).
class StopOffset {
  const StopOffset(this.stop, this.seconds);
  final int stop;
  final int seconds;
}

/// Wall-clock seconds from [serviceDate]'s midnight to [t]; past midnight counts on (24:20 is 87600).
int secondsInServiceDay(DateTime serviceDate, DateTime t) {
  final days = DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(serviceDate.year, serviceDate.month, serviceDate.day)).inDays;
  return days * Duration.secondsPerDay + t.hour * 3600 + t.minute * 60 + t.second;
}

/// Gives each walk its start: walks before the first ride end just as it leaves (the rider leaves as late as they
/// can); every other walk starts when the leg before it ends.
List<Leg> retimeWalks(List<Leg> legs) {
  final firstRide = legs.indexWhere((l) => l is RideLeg);
  if (firstRide < 0) return legs;
  var t = legs[firstRide].startSeconds;
  for (var i = firstRide - 1; i >= 0; i--) {
    t -= (legs[i] as WalkLeg).seconds;
  }
  final out = <Leg>[];
  for (final leg in legs) {
    out.add(leg is WalkLeg
        ? WalkLeg(fromStopId: leg.fromStopId, toStopId: leg.toStopId, seconds: leg.seconds, startSeconds: t)
        : leg);
    t = out.last.endSeconds;
  }
  return out;
}

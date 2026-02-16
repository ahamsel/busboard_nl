import '../../data/gtfs/gtfs_repository.dart';
import '../../data/gtfs/gtfs_time.dart';
import '../../data/realtime/metrobus_mobile_api.dart';
import '../../data/realtime/timetrack_models.dart';
import '../../data/realtime/timetrack_api.dart';
import 'arrival_models.dart';

/// Computes upcoming arrivals for a given stop.
///
/// Joins GTFS schedule data with optional TimeTrack live data
/// to produce a sorted list of upcoming departures.
class ArrivalService {
  final GtfsRepository repository;

  const ArrivalService(this.repository);

  /// Get upcoming departures for [stopId] at [now].
  ///
  /// Returns up to [maxResults] departures sorted by soonest.
  /// If [liveVehicles] is provided, merges live ETA adjustments.
  List<ArrivalRow> getUpcomingArrivals({
    required String stopId,
    required DateTime now,
    int maxResults = 15,
    List<TimeTrackVehicle>? liveVehicles,
    List<MetrobusDeparture>? scrapedDepartures,
  }) {
    if (!repository.isLoaded) return [];

    // Get stop times for this stop
    final stopTimes = repository.stopTimesByStopId[stopId];
    if (stopTimes == null || stopTimes.isEmpty) return [];

    // Determine active services for today
    final today = DateTime(now.year, now.month, now.day);
    final activeServices = repository.activeServiceIds(today);

    // Also check previous day for after-midnight trips (>24:00)
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayServices = repository.activeServiceIds(yesterday);

    // Current time as GTFS time (seconds since midnight)
    final nowTime = GtfsTime.fromDateTime(now);

    // Build live vehicle index if available
    final liveIndex = liveVehicles != null
        ? TimeTrackApi.buildTripIndex(liveVehicles)
        : <String, TimeTrackVehicle>{};

    final arrivals = <ArrivalRow>[];

    for (final st in stopTimes) {
      final trip = repository.tripsById[st.tripId];
      if (trip == null) continue;

      final route = repository.routesById[trip.routeId];
      if (route == null) continue;

      // Parse GTFS departure time
      final GtfsTime departureTime;
      try {
        departureTime = GtfsTime.parse(st.departureTime);
      } catch (_) {
        continue;
      }

      // Determine if this trip is active today
      bool isActive = false;
      if (departureTime.isNextDay) {
        // After-midnight trip — check if yesterday's service includes this
        isActive = yesterdayServices.contains(trip.serviceId);
      } else {
        isActive = activeServices.contains(trip.serviceId);
      }
      if (!isActive) continue;

      // Calculate minutes away (raw scheduled — may be in the past for late buses)
      final minutesAway = departureTime.minutesFrom(nowTime);
      // Skip if more than 3 hours away
      if (minutesAway > 180) continue;

      // Check for live data
      final liveVehicle = liveIndex[st.tripId];
      GtfsTime? predictedTime;
      LiveStatus? liveStatus;
      bool isLive = false;
      String? vehicleNumber;
      int? schedDiffMins;

      if (liveVehicle != null) {
        isLive = true;
        vehicleNumber = liveVehicle.vehicle;
        schedDiffMins = liveVehicle.gtfsStopSequenceSchedDifferenceMins;

        // Apply prediction:
        // diff positive = bus is AHEAD of schedule → arrives earlier
        // diff negative = bus is BEHIND schedule → arrives later
        // predicted = scheduled - diff_minutes
        final adjustedSeconds =
            departureTime.totalSeconds - (schedDiffMins * 60);
        predictedTime = GtfsTime.fromSeconds(adjustedSeconds);

        // Determine live status
        if (schedDiffMins > 0) {
          liveStatus = LiveStatus.ahead;
        } else if (schedDiffMins < 0) {
          liveStatus = LiveStatus.behind;
        } else {
          liveStatus = LiveStatus.onTime;
        }
      }

      // Calculate minutes away using predicted or scheduled time
      final effectiveTime = predictedTime ?? departureTime;
      final effectiveMinutes = effectiveTime.minutesFrom(nowTime);
      if (effectiveMinutes < -1) continue; // Already departed

      arrivals.add(
        ArrivalRow(
          routeShortName: route.routeShortName,
          headsign: trip.tripHeadsign,
          scheduledTime: departureTime,
          predictedTime: predictedTime,
          minutesAway: effectiveMinutes < 0 ? 0 : effectiveMinutes,
          liveStatus: liveStatus,
          isLive: isLive,
          tripId: st.tripId,
          vehicleNumber: vehicleNumber,
          schedDiffMins: schedDiffMins,
        ),
      );
    }

    // Merge scraped predictions if available
    if (scrapedDepartures != null && scrapedDepartures.isNotEmpty) {
      _mergeScrapedDepartures(arrivals, scrapedDepartures, nowTime);
    }

    // Sort by soonest departure
    arrivals.sort((a, b) => a.minutesAway.compareTo(b.minutesAway));

    // Return up to maxResults
    return arrivals.take(maxResults).toList();
  }

  /// Merge scraped departure predictions into the arrivals list.
  ///
  /// Matches by route short name + scheduled time within 5 minutes,
  /// then overrides the predicted time with the scraped prediction.
  void _mergeScrapedDepartures(
    List<ArrivalRow> arrivals,
    List<MetrobusDeparture> scraped,
    GtfsTime nowTime,
  ) {
    for (var i = 0; i < arrivals.length; i++) {
      final arrival = arrivals[i];

      // Find best matching scraped departure
      MetrobusDeparture? bestMatch;
      int bestTimeDiff = 6; // Must be within 5 minutes

      for (final dep in scraped) {
        // Match route short name
        if (dep.routeShortName != arrival.routeShortName) continue;

        // Parse the scraped scheduled time and compare
        final scrapedSchedTime =
            MetrobusDeparture.parseTimeToGtfs(dep.scheduledTime);
        if (scrapedSchedTime == null) continue;

        final timeDiff =
            (scrapedSchedTime.totalSeconds - arrival.scheduledTime.totalSeconds)
                .abs() ~/
            60;

        if (timeDiff < bestTimeDiff) {
          bestTimeDiff = timeDiff;
          bestMatch = dep;
        }
      }

      if (bestMatch == null) continue;

      // Parse the scraped predicted time
      final scrapedPredTime =
          MetrobusDeparture.parseTimeToGtfs(bestMatch.predictedTime);
      if (scrapedPredTime == null) continue;

      // Override with scraped prediction
      final effectiveMinutes = scrapedPredTime.minutesFrom(nowTime);
      if (effectiveMinutes < -1) continue; // Already departed

      // Determine live status from scraped data
      final scrapedSchedTime =
          MetrobusDeparture.parseTimeToGtfs(bestMatch.scheduledTime);
      LiveStatus? newStatus = arrival.liveStatus;
      if (scrapedSchedTime != null) {
        final diff = scrapedSchedTime.totalSeconds - scrapedPredTime.totalSeconds;
        if (diff > 60) {
          newStatus = LiveStatus.ahead;
        } else if (diff < -60) {
          newStatus = LiveStatus.behind;
        } else {
          newStatus = LiveStatus.onTime;
        }
      }

      arrivals[i] = ArrivalRow(
        routeShortName: arrival.routeShortName,
        headsign: arrival.headsign,
        scheduledTime: arrival.scheduledTime,
        predictedTime: scrapedPredTime,
        minutesAway: effectiveMinutes < 0 ? 0 : effectiveMinutes,
        liveStatus: newStatus,
        isLive: true,
        tripId: arrival.tripId,
        vehicleNumber: arrival.vehicleNumber ?? bestMatch.vehicle,
        schedDiffMins: arrival.schedDiffMins,
        isEnhanced: true,
      );
    }
  }
}

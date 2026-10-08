import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';

/// A GTFS-RT vehicle as `TimeTrackApi` builds it: [diff] positive is ahead; null is "no delay data".
TimeTrackVehicle fakeVehicle({String trip = 't1', String id = '1415', int? diff = -6, required DateTime fix}) =>
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

TimeTrackFetchResult fakeFeed(List<TimeTrackVehicle> v, {Map<String, Map<String, List<FeedStopTime>>>? stopTimes}) =>
    TimeTrackFetchResult.success(v, source: LiveDataSource.gtfsRealtime, stopTimes: stopTimes ?? const {});

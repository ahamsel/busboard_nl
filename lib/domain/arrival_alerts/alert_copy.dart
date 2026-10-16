import '../../data/gtfs/headsign.dart';
import '../../ui/kit/bb_time.dart';
import 'alert_tracker.dart';
import 'arrival_alert.dart';

/// One notification's text.
class AlertMessage {
  const AlertMessage(this.title, this.body, {this.route});
  final String title;
  final String body;

  /// The app route a tap opens, if any.
  final String? route;
}

String _mins(int m) => m == 1 ? '1 min' : '$m min';

/// The alert itself (spec §2.3). [estimateFrom] makes it the iPhone's scheduled estimate.
AlertMessage alertMessage(
  ArrivalAlert a, {
  required AlertSource source,
  required int minutesAway,
  DateTime? estimateFrom,
  required bool use24h,
}) {
  final route = 'Route ${a.routeShortName}';
  final place = '${a.stopName} (stop ${a.stopId})';
  final timetable = source != AlertSource.live;
  final String title;
  if (minutesAway <= 0) {
    title = '$route is due now';
  } else if (timetable) {
    title = '$route is scheduled in about ${_mins(minutesAway)}';
  } else if (estimateFrom != null) {
    title = '$route should be about ${_mins(minutesAway)} away';
  } else {
    title = '$route is about ${_mins(minutesAway)} away';
  }
  final String body;
  if (timetable) {
    body = '$place · no live tracking for this trip';
  } else if (estimateFrom != null) {
    body = 'Estimate from ${BBTime.of(estimateFrom, use24h: use24h)}. Open BusBoard for the latest.';
  } else {
    body = place;
  }
  return AlertMessage(title, body, route: a.boardRoute);
}

/// The Android countdown's title (spec §2.2).
String ongoingTitle(ArrivalAlert a) => 'Route ${a.routeShortName} to ${readableHeadsign(a.headsign)}';

/// The Android countdown's line.
String ongoingText(AlertStep s) {
  if (s.minutesAway <= 0) return 'Due now';
  final about = 'about ${_mins(s.minutesAway)}';
  return switch (s.source) {
    AlertSource.live => 'About ${_mins(s.minutesAway)} · live',
    AlertSource.timetable => 'About ${_mins(s.minutesAway)} · scheduled',
    AlertSource.lost => 'Live tracking lost · using the timetable · $about',
  };
}

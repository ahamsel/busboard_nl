// GTFS data models for BusBoard NL.
//
// These models correspond to the parsed GTFS CSV files:
// stops.txt, routes.txt, trips.txt, stop_times.txt,
// calendar.txt, calendar_dates.txt.

class StopInfo {
  final String stopId;
  final String stopName;
  final double stopLat;
  final double stopLon;

  const StopInfo({
    required this.stopId,
    required this.stopName,
    required this.stopLat,
    required this.stopLon,
  });

  @override
  String toString() => 'StopInfo($stopId: $stopName)';
}

class RouteInfo {
  final String routeId;
  final String routeShortName;
  final String routeLongName;

  const RouteInfo({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
  });

  @override
  String toString() => 'RouteInfo($routeId: $routeShortName)';
}

class TripInfo {
  final String tripId;
  final String routeId;
  final String serviceId;
  final String tripHeadsign;
  final int directionId;
  final String? shapeId;

  const TripInfo({
    required this.tripId,
    required this.routeId,
    required this.serviceId,
    required this.tripHeadsign,
    required this.directionId,
    this.shapeId,
  });

  @override
  String toString() => 'TripInfo($tripId: $tripHeadsign)';
}

class StopTimeRow {
  final String tripId;
  final String arrivalTime; // raw HH:MM:SS string (may be >24:00)
  final String departureTime; // raw HH:MM:SS string (may be >24:00)
  final String stopId;
  final int stopSequence;

  const StopTimeRow({
    required this.tripId,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopId,
    required this.stopSequence,
  });

  @override
  String toString() => 'StopTimeRow($tripId@$stopId: $departureTime)';
}

class ServiceCalendar {
  final String serviceId;
  final bool monday;
  final bool tuesday;
  final bool wednesday;
  final bool thursday;
  final bool friday;
  final bool saturday;
  final bool sunday;
  final DateTime startDate;
  final DateTime endDate;

  const ServiceCalendar({
    required this.serviceId,
    required this.monday,
    required this.tuesday,
    required this.wednesday,
    required this.thursday,
    required this.friday,
    required this.saturday,
    required this.sunday,
    required this.startDate,
    required this.endDate,
  });

  /// Check if this calendar runs on [date].
  bool runsOn(DateTime date) {
    if (date.isBefore(startDate) || date.isAfter(endDate)) return false;
    switch (date.weekday) {
      case DateTime.monday:
        return monday;
      case DateTime.tuesday:
        return tuesday;
      case DateTime.wednesday:
        return wednesday;
      case DateTime.thursday:
        return thursday;
      case DateTime.friday:
        return friday;
      case DateTime.saturday:
        return saturday;
      case DateTime.sunday:
        return sunday;
      default:
        return false;
    }
  }
}

/// One row of transfers.txt.
class TransferRule {
  final String fromStopId;
  final String toStopId;

  /// GTFS transfer_type: 0 recommended, 1 timed, 2 needs [minTransferSeconds], 3 not possible.
  final int transferType;
  final int? minTransferSeconds;

  const TransferRule({
    required this.fromStopId,
    required this.toStopId,
    required this.transferType,
    this.minTransferSeconds,
  });
}

/// Exception types for calendar_dates.txt.
enum ExceptionType {
  added, // 1 = service added
  removed, // 2 = service removed
}

class CalendarDate {
  final String serviceId;
  final DateTime date;
  final ExceptionType exceptionType;

  const CalendarDate({
    required this.serviceId,
    required this.date,
    required this.exceptionType,
  });
}

/// Lightweight entry linking a route's short name to a trip's shape.
/// Used for fallback shape matching when gtfsTripId is unavailable.
class TripShapeEntry {
  final String tripId;
  final String shapeId;
  final String headsign;
  final int directionId;
  final String serviceId;

  const TripShapeEntry({
    required this.tripId,
    required this.shapeId,
    required this.headsign,
    required this.directionId,
    required this.serviceId,
  });
}

class ShapePoint {
  final String shapeId;
  final double lat;
  final double lon;
  final int sequence;
  final double? distTraveled;

  const ShapePoint({
    required this.shapeId,
    required this.lat,
    required this.lon,
    required this.sequence,
    this.distTraveled,
  });
}

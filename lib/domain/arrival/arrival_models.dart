import '../../data/gtfs/gtfs_time.dart';

/// Status of a live prediction.
enum LiveStatus {
  ahead,
  behind,
  onTime;

  String get label {
    switch (this) {
      case LiveStatus.ahead:
        return 'AHEAD';
      case LiveStatus.behind:
        return 'BEHIND';
      case LiveStatus.onTime:
        return 'ON TIME';
    }
  }
}

/// A single row on the arrival board.
class ArrivalRow {
  /// Route short name (e.g., "1", "2", "10").
  final String routeShortName;

  /// Trip headsign (e.g., "Crosbie Rd - The Village").
  final String headsign;

  /// Scheduled departure time as GTFS time.
  final GtfsTime scheduledTime;

  /// Predicted departure time (adjusted by live data), or null.
  final GtfsTime? predictedTime;

  /// Minutes until departure from now.
  final int minutesAway;

  /// Live status if available.
  final LiveStatus? liveStatus;

  /// Whether this row has live data.
  final bool isLive;

  /// Trip ID for matching.
  final String tripId;

  /// Vehicle number if live.
  final String? vehicleNumber;

  /// Schedule difference in minutes from live (positive=ahead, negative=behind).
  final int? schedDiffMins;

  const ArrivalRow({
    required this.routeShortName,
    required this.headsign,
    required this.scheduledTime,
    this.predictedTime,
    required this.minutesAway,
    this.liveStatus,
    this.isLive = false,
    required this.tripId,
    this.vehicleNumber,
    this.schedDiffMins,
  });

  /// The display time (predicted if available, otherwise scheduled).
  GtfsTime get displayTime => predictedTime ?? scheduledTime;

  /// Display the scheduled time as HH:MM.
  String get scheduledDisplay => scheduledTime.toDisplayString();

  /// Display countdown text.
  String get countdownText {
    if (minutesAway <= 0) return 'NOW';
    if (minutesAway == 1) return '1 min';
    return '$minutesAway min';
  }

  @override
  String toString() =>
      'ArrivalRow($routeShortName → $headsign @ $scheduledDisplay, '
      '${isLive ? "LIVE ${liveStatus?.label}" : "scheduled"}, '
      'in $minutesAway min)';
}

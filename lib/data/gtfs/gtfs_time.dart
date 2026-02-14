// Parses GTFS time strings (HH:MM:SS), including times >24:00:00.
//
// In GTFS, times can exceed 24:00:00 to indicate trips that extend
// past midnight. For example, "25:10:00" means 1:10 AM the next day.

class GtfsTime implements Comparable<GtfsTime> {
  /// Total seconds since midnight of the service day.
  final int totalSeconds;

  const GtfsTime._(this.totalSeconds);

  /// Parse a GTFS time string like "08:30:00" or "25:10:00".
  factory GtfsTime.parse(String timeStr) {
    final parts = timeStr.trim().split(':');
    if (parts.length != 3) {
      throw FormatException('Invalid GTFS time format: $timeStr');
    }
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final seconds = int.parse(parts[2]);
    return GtfsTime._(hours * 3600 + minutes * 60 + seconds);
  }

  /// Create from total seconds.
  factory GtfsTime.fromSeconds(int totalSeconds) => GtfsTime._(totalSeconds);

  /// Hours component (can be >23 for GTFS after-midnight times).
  int get hours => totalSeconds ~/ 3600;

  /// Minutes component.
  int get minutes => (totalSeconds % 3600) ~/ 60;

  /// Seconds component.
  int get seconds => totalSeconds % 60;

  /// Whether this time wraps past midnight (hours >= 24).
  bool get isNextDay => hours >= 24;

  /// Convert to a [DateTime] given the service date.
  ///
  /// If hours >= 24, the resulting DateTime will be on the next calendar day.
  /// The service date should be a date-only DateTime (no time component).
  DateTime toDateTime(DateTime serviceDate) {
    final normalHours = hours % 24;
    final extraDays = hours ~/ 24;
    return DateTime(
      serviceDate.year,
      serviceDate.month,
      serviceDate.day + extraDays,
      normalHours,
      minutes,
      seconds,
    );
  }

  /// Display as HH:MM (24h format, normalised).
  String toDisplayString() {
    final h = hours % 24;
    final m = minutes;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Difference in minutes from [other] to this time.
  int minutesFrom(GtfsTime other) {
    return (totalSeconds - other.totalSeconds) ~/ 60;
  }

  /// Create a GtfsTime representing "now" for the current service day.
  ///
  /// If [now] is between midnight and ~3:00 AM, it might belong to the
  /// previous service day. The caller must handle service day logic.
  factory GtfsTime.fromDateTime(DateTime now) {
    return GtfsTime._(now.hour * 3600 + now.minute * 60 + now.second);
  }

  @override
  int compareTo(GtfsTime other) => totalSeconds.compareTo(other.totalSeconds);

  @override
  bool operator ==(Object other) =>
      other is GtfsTime && totalSeconds == other.totalSeconds;

  @override
  int get hashCode => totalSeconds.hashCode;

  bool operator <(GtfsTime other) => totalSeconds < other.totalSeconds;
  bool operator <=(GtfsTime other) => totalSeconds <= other.totalSeconds;
  bool operator >(GtfsTime other) => totalSeconds > other.totalSeconds;
  bool operator >=(GtfsTime other) => totalSeconds >= other.totalSeconds;

  @override
  String toString() =>
      '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

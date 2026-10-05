/// Puts a capture's UTC fetch times on the feed's local wall clock.
///
/// The store reads the feed's `positionTimeSeconds` as local wall-clock time
/// and builds GPS times from calendar fields in the machine's timezone, so a
/// replay is only coherent if the fetch times carry that same wall clock. A
/// capture records fetch times in UTC, so this derives the capture's UTC
/// offset from the frames themselves and rebuilds each fetch time as a local
/// `DateTime` with that wall clock. The replay then behaves the same in any
/// machine timezone (no DST change inside a capture is assumed).
class ReplayClock {
  ReplayClock._(this.offset);

  /// Local minus UTC for the capture, a multiple of 30 minutes in -12..12 h.
  final Duration offset;

  /// Derives the offset from `frames` (decoded capture.json frames): the
  /// median over the vehicles of the first frame that has any of
  /// `fetch_time` (UTC seconds of day) minus `positionTimeSeconds`, folded
  /// into +-12 h and rounded to 30 minutes. That difference is the feed's
  /// GPS age minus the offset, and the age is far smaller than 15 minutes.
  factory ReplayClock.fromFrames(List<Map<String, dynamic>> frames) {
    const day = Duration.secondsPerDay;
    for (final frame in frames) {
      final utc = DateTime.parse(frame['fetch_time'] as String).toUtc();
      final utcSeconds = utc.hour * 3600 + utc.minute * 60 + utc.second;
      final diffs = <int>[
        for (final v in (frame['vehicles'] as List).cast<Map<String, dynamic>>())
          if (((v['positionTimeSeconds'] as num?) ?? 0) > 0 && (v['positionTimeSeconds'] as num) < day)
            utcSeconds - (v['positionTimeSeconds'] as num).toInt(),
      ]..sort();
      if (diffs.isEmpty) continue;
      final median = diffs[diffs.length ~/ 2];
      final folded = ((median + day ~/ 2) % day) - day ~/ 2;
      final halfHours = (folded / 1800).round();
      return ReplayClock._(Duration(seconds: -halfHours * 1800));
    }
    throw StateError('no vehicle with a position time in the capture');
  }

  /// [utc] as a local `DateTime` whose wall clock is the capture's local time.
  DateTime toLocal(DateTime utc) {
    final w = utc.toUtc().add(offset);
    return DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second, w.millisecond, w.microsecond);
  }
}

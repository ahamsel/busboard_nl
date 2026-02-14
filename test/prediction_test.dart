import 'package:flutter_test/flutter_test.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';

void main() {
  group('Prediction sign correctness', () {
    test('bus AHEAD of schedule: diff +2 → predicted earlier', () {
      // Scheduled 14:00, diff_mins = +2 (bus is 2 min AHEAD)
      // predicted = scheduled - diff = 14:00 - 2min = 13:58
      final scheduled = GtfsTime.parse('14:00:00');
      const diffMins = 2; // positive = ahead

      final predictedSeconds = scheduled.totalSeconds - (diffMins * 60);
      final predicted = GtfsTime.fromSeconds(predictedSeconds);

      expect(predicted.hours, 13);
      expect(predicted.minutes, 58);
      expect(predicted.toDisplayString(), '13:58');
    });

    test('bus BEHIND schedule: diff -5 → predicted later', () {
      // Scheduled 14:00, diff_mins = -5 (bus is 5 min BEHIND)
      // predicted = scheduled - (-5min) = 14:00 + 5min = 14:05
      final scheduled = GtfsTime.parse('14:00:00');
      const diffMins = -5; // negative = behind

      final predictedSeconds = scheduled.totalSeconds - (diffMins * 60);
      final predicted = GtfsTime.fromSeconds(predictedSeconds);

      expect(predicted.hours, 14);
      expect(predicted.minutes, 5);
      expect(predicted.toDisplayString(), '14:05');
    });

    test('bus ON TIME: diff 0 → predicted = scheduled', () {
      final scheduled = GtfsTime.parse('14:00:00');
      const diffMins = 0;

      final predictedSeconds = scheduled.totalSeconds - (diffMins * 60);
      final predicted = GtfsTime.fromSeconds(predictedSeconds);

      expect(predicted, scheduled);
      expect(predicted.toDisplayString(), '14:00');
    });

    test('large ahead diff', () {
      // Scheduled 14:00, diff = +10 → predicted 13:50
      final scheduled = GtfsTime.parse('14:00:00');
      const diffMins = 10;

      final predictedSeconds = scheduled.totalSeconds - (diffMins * 60);
      final predicted = GtfsTime.fromSeconds(predictedSeconds);

      expect(predicted.toDisplayString(), '13:50');
    });

    test('large behind diff', () {
      // Scheduled 14:00, diff = -15 → predicted 14:15
      final scheduled = GtfsTime.parse('14:00:00');
      const diffMins = -15;

      final predictedSeconds = scheduled.totalSeconds - (diffMins * 60);
      final predicted = GtfsTime.fromSeconds(predictedSeconds);

      expect(predicted.toDisplayString(), '14:15');
    });
  });
}

/// Configurable thresholds for anomaly detection in bus journey tracing.
class AnomalyThresholds {
  /// Progress decreased by more than this many meters.
  final double backwardJumpMeters;

  /// Position jumped more than this many meters in a single frame.
  final double teleportMeters;

  /// Position unchanged for more than this many seconds while bus should move.
  final double freezeSeconds;

  /// Displayed speed exceeded this value.
  final double speedSpikeKmh;

  /// After blend ended, rendered position still this far from target.
  final double blendFailureMeters;

  const AnomalyThresholds({
    this.backwardJumpMeters = 5.0,
    this.teleportMeters = 200.0,
    this.freezeSeconds = 10.0,
    this.speedSpikeKmh = 120.0,
    this.blendFailureMeters = 50.0,
  });
}

enum AnomalyType {
  backwardJump,
  teleport,
  freeze,
  speedSpike,
  blendFailure,
}

/// A detected anomaly in a bus's visual journey.
class Anomaly {
  final AnomalyType type;
  final double elapsedSeconds;
  final String busKey;
  final String description;
  final double? magnitudeMeters;

  const Anomaly({
    required this.type,
    required this.elapsedSeconds,
    required this.busKey,
    required this.description,
    this.magnitudeMeters,
  });

  @override
  String toString() {
    final mag =
        magnitudeMeters != null
            ? ' (${magnitudeMeters!.toStringAsFixed(1)}m)'
            : '';
    return '!! ${type.name.toUpperCase()}$mag at t=${elapsedSeconds.toStringAsFixed(1)}s: $description';
  }
}

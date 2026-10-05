/// Turns each drawn heading toward the renderer's heading the short way round,
/// at most [maxDegreesPerSecond], so a bus's heading notch never spins through
/// 180° at a shape vertex or after a trip change. Snaps on the first frame and
/// after a render gap over [snapGap]. One instance per map; call [prune] with
/// the vehicles still drawn.
class HeadingSmoother {
  static const double maxDegreesPerSecond = 180;
  static const Duration snapGap = Duration(seconds: 2);

  final _state = <String, ({double heading, DateTime at})>{};

  double smooth(String vehicleId, double target, DateTime now) {
    final goal = _norm(target);
    final prev = _state[vehicleId];
    double out;
    if (prev == null) {
      out = goal;
    } else {
      final dt = now.difference(prev.at);
      if (dt <= Duration.zero) return prev.heading;
      if (dt > snapGap) {
        out = goal;
      } else {
        final diff = shortestDelta(prev.heading, goal);
        final step = maxDegreesPerSecond * dt.inMicroseconds / Duration.microsecondsPerSecond;
        out = diff.abs() <= step ? goal : _norm(prev.heading + step * diff.sign);
      }
    }
    _state[vehicleId] = (heading: out, at: now);
    return out;
  }

  void prune(Set<String> keep) => _state.removeWhere((id, _) => !keep.contains(id));

  /// Signed turn from [from] to [to] in (-180, 180].
  static double shortestDelta(double from, double to) {
    final d = (to - from) % 360;
    return d > 180 ? d - 360 : d;
  }

  static double _norm(double heading) => heading % 360;
}

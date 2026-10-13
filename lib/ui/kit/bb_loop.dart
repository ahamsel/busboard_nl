import 'dart:async';

import 'package:flutter/widgets.dart';

/// A looping effect that runs for its controller's duration, rests for [rest], and runs again
/// (spec §3.1 `pulse`). The rests leave frame-free gaps: a screen with a loop still settles
/// between cycles, and the loop costs nothing while it rests. [run] starts or stops it; callers
/// pass whether motion is allowed, so under Reduce Motion it never starts.
class BBLoop {
  BBLoop({required TickerProvider vsync, required Duration active, required this.rest})
      : controller = AnimationController(vsync: vsync, duration: active) {
    controller.addStatusListener(_onStatus);
  }

  final AnimationController controller;
  final Duration rest;
  Timer? _timer;
  bool _running = false;

  bool get isRunning => _running;

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_running) return;
    _timer?.cancel();
    _timer = Timer(rest, () {
      if (_running) controller.forward(from: 0);
    });
  }

  /// Starts the loop when [on]; otherwise stops it at 0 (the resting look).
  void run(bool on) {
    if (on == _running) return;
    _running = on;
    _timer?.cancel();
    if (on) {
      controller.forward(from: 0);
    } else {
      controller.stop();
      controller.value = 0;
    }
  }

  void dispose() {
    _running = false;
    _timer?.cancel();
    controller.dispose();
  }
}

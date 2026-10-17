import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Phones run upright; tablets turn freely. A phone is a screen whose shorter side is under
/// [phoneShortestSide] logical pixels (the usual Android breakpoint), so a phone held sideways is still a
/// phone. Checked at launch and again when the screen changes, as when a foldable opens.
///
/// On iPhone the Info.plist allows only portrait as well, so the launch screen is upright too; iPad keeps
/// every orientation there, as split-screen multitasking needs.
class OrientationLock with WidgetsBindingObserver {
  OrientationLock({Size Function()? viewSize, Future<void> Function(List<DeviceOrientation>)? setOrientations})
      : _viewSize = viewSize ?? _firstViewSize,
        _set = setOrientations ?? SystemChrome.setPreferredOrientations;

  static const double phoneShortestSide = 600;

  /// Portrait only on a phone; an empty list (every orientation) on a tablet.
  static List<DeviceOrientation> orientationsFor(Size logicalSize) =>
      logicalSize.shortestSide < phoneShortestSide ? const [DeviceOrientation.portraitUp] : const [];

  final Size Function() _viewSize;
  final Future<void> Function(List<DeviceOrientation>) _set;
  List<DeviceOrientation>? _applied;

  /// Applies the lock now and follows later screen changes.
  void attach() {
    WidgetsBinding.instance.addObserver(this);
    apply();
  }

  @override
  void didChangeMetrics() => apply();

  /// Sets the orientations for the current screen, when they differ from the last ones set.
  void apply() {
    final size = _viewSize();
    if (size.isEmpty) return; // no view yet
    final next = orientationsFor(size);
    if (_applied != null && listEquals(_applied, next)) return;
    _applied = next;
    unawaited(_set(next));
  }

  static Size _firstViewSize() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return Size.zero;
    final view = views.first;
    return view.physicalSize / view.devicePixelRatio;
  }
}

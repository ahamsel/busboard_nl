// Demo-video support: compiled in only with --dart-define=DEMO_TOUR=true.
// integration_test/demo_tour_test.dart drives the app for a screen recording;
// this file shows where each touch lands and gives the script the map's camera.
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../ui/map/map_layers.dart';

const kDemoTour = bool.fromEnvironment('DEMO_TOUR');

/// What the map screen hands the tour script: its camera, its own tap
/// handler (a native map tap goes through it) and the buses as drawn.
class DemoMapHooks {
  DemoMapHooks({required this.controller, required this.tap, required this.selectStop, required this.markers});

  final MapLibreMapController controller;
  final void Function(LatLng tap) tap;

  /// Opens a stop's card, as a tap on it does when no bus is parked on top.
  final void Function(String stopId) selectStop;
  final List<BusMarker> Function() markers;

  static DemoMapHooks? current;
}

/// Fingers the script draws itself, for gestures it performs through the
/// map camera rather than as pointer events (the map is a native view).
final demoGhostFingers = ValueNotifier<List<Offset>>(const []);

/// Draws a soft dot under every touch, and a short fade after it lifts.
class DemoTouches extends StatefulWidget {
  const DemoTouches({super.key, required this.child});

  final Widget child;

  @override
  State<DemoTouches> createState() => _DemoTouchesState();
}

class _DemoTouchesState extends State<DemoTouches> with SingleTickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 380);
  final _down = <int, Offset>{};
  final _lifts = <(Offset, DateTime)>[];
  late final Ticker _ticker = createTicker((_) {
    final now = DateTime.now();
    _lifts.removeWhere((l) => now.difference(l.$2) > _fade);
    setState(() {});
    if (_lifts.isEmpty) _ticker.stop();
  });

  void _lift(int pointer) {
    final at = _down.remove(pointer);
    if (at != null) _lifts.add((at, DateTime.now()));
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => setState(() => _down[e.pointer] = e.position),
      onPointerMove: (e) => setState(() => _down[e.pointer] = e.position),
      onPointerUp: (e) => setState(() => _lift(e.pointer)),
      onPointerCancel: (e) => setState(() => _lift(e.pointer)),
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<List<Offset>>(
                valueListenable: demoGhostFingers,
                builder: (context, ghosts, _) => CustomPaint(
                  painter: _TouchPainter(
                    down: [..._down.values, ...ghosts],
                    lifts: [
                      for (final (at, liftedAt) in _lifts)
                        (at, 1 - now.difference(liftedAt).inMilliseconds / _fade.inMilliseconds),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TouchPainter extends CustomPainter {
  _TouchPainter({required this.down, required this.lifts});

  final List<Offset> down;
  final List<(Offset, double)> lifts;

  static const _radius = 22.0;

  void _dot(Canvas canvas, Offset at, double opacity, double scale) {
    final r = _radius * scale;
    canvas.drawCircle(at, r, Paint()..color = const Color(0xFF1B2A3A).withValues(alpha: 0.22 * opacity));
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * opacity),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final at in down) {
      _dot(canvas, at, 1, 1);
    }
    for (final (at, left) in lifts) {
      final t = left.clamp(0.0, 1.0);
      _dot(canvas, at, t, 1 + (1 - t) * 0.5);
    }
  }

  @override
  bool shouldRepaint(_TouchPainter old) => true;
}

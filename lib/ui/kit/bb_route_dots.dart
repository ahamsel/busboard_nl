import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'route_palette.dart';
import 'tokens.dart';

/// BusBoard's progress mark: three dots in route colours. With [progress]
/// (0..1) they grow in turn, as while pulling to refresh; with no progress
/// they hop in sequence. Reduce motion shows them filled and still.
/// Decorative: callers carry the meaning in their own semantics.
class BBRouteDots extends StatefulWidget {
  const BBRouteDots({super.key, this.progress, this.dotSize = 10});

  final double? progress;
  final double dotSize;

  static const List<RouteHue> hues = [RouteHue.red, RouteHue.yellow, RouteHue.green];

  @override
  State<BBRouteDots> createState() => _BBRouteDotsState();
}

class _BBRouteDotsState extends State<BBRouteDots> with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = BBMotion.of(context, BBMotion.standard) == Duration.zero;
    _syncTicker();
  }

  @override
  void didUpdateWidget(BBRouteDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final shouldHop = widget.progress == null && !_reduceMotion;
    if (shouldHop && !_hop.isAnimating) {
      _hop.repeat();
    } else if (!shouldHop && _hop.isAnimating) {
      _hop.stop();
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  Matrix4 _transformFor(int i) {
    final progress = widget.progress;
    if (progress != null) {
      final f = (progress.clamp(0.0, 1.0) * 3 - i).clamp(0.0, 1.0);
      final s = 0.4 + 0.6 * f;
      return Matrix4.diagonal3Values(s, s, s);
    }
    if (_reduceMotion) return Matrix4.identity();
    // Each dot rises during the first 40% of its own phase, ~117 ms apart (0.13 of the 900 ms loop).
    final t = (_hop.value - i * 0.13) % 1.0;
    final rise = t < 0.4 ? math.sin(t / 0.4 * math.pi) : 0.0;
    return Matrix4.translationValues(0, -rise * widget.dotSize * 0.7, 0);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = context.bb.brightness;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _hop,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.dotSize * 0.3),
                child: Transform(
                  key: ValueKey('bb-route-dot-$i'),
                  alignment: Alignment.center,
                  transform: _transformFor(i),
                  child: Opacity(
                    opacity: widget.progress == null
                        ? 1
                        : 0.35 + 0.65 * (widget.progress!.clamp(0.0, 1.0) * 3 - i).clamp(0.0, 1.0),
                    child: Container(
                      width: widget.dotSize,
                      height: widget.dotSize,
                      decoration: BoxDecoration(
                        color: brightness == Brightness.dark ? BBRouteDots.hues[i].fillDark : BBRouteDots.hues[i].line,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

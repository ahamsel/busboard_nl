import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'bb_loop.dart';
import 'glyphs/bb_glyph.dart';
import 'tokens.dart';

/// Text that rolls when it changes (spec §3.2, minutes 7 → 6): the new value rises in from below
/// as the old one rises out and fades, over [BBMotion.standard]. Instant under Reduce Motion.
class BBRollingText extends StatelessWidget {
  const BBRollingText(this.text, {super.key, required this.style, this.alignment = Alignment.centerRight});

  final String text;
  final TextStyle style;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: BBMotion.of(context, BBMotion.standard),
      switchInCurve: BBMotion.curve,
      switchOutCurve: BBMotion.curve,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, clipBehavior: Clip.none, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        // The outgoing value's animation runs in reverse, so "up" for both reads as a roll.
        final incoming = child.key == ValueKey(text);
        // Only the new value is announced: mid-roll the old one is decoration (a merged row would
        // otherwise read "7 6").
        if (!incoming) child = ExcludeSemantics(child: child);
        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(Tween(begin: Offset(0, incoming ? 0.6 : -0.6), end: Offset.zero)),
              child: child,
            ),
          ),
        );
      },
      child: Text(text, key: ValueKey(text), style: style),
    );
  }
}

/// Plays once when [active] turns true after the first build (a row becoming "Now", spec §3.2):
/// the child swells to 1.08 and back over [BBMotion.nowPulse], and a brand edge glows and fades.
/// Nothing for a row that is already "Now" when it first shows, and nothing under Reduce Motion.
class BBNowPulse extends StatefulWidget {
  const BBNowPulse({super.key, required this.active, required this.child, this.radius = BBRadius.card});

  final bool active;
  final Widget child;
  final double radius;

  @override
  State<BBNowPulse> createState() => _BBNowPulseState();
}

class _BBNowPulseState extends State<BBNowPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: BBMotion.nowPulse);
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = BBMotion.reduced(context);
    if (_reduced) {
      // Reduce Motion turned on mid-pulse: stop at rest.
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void didUpdateWidget(BBNowPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_reduced) _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.bb.colors.brand;
    return AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final wave = math.sin(math.pi * _pulse.value); // 0 → 1 → 0
        // One shape at rest and mid-pulse, so the child keeps its state.
        return Transform.scale(
          scale: 1 + 0.08 * wave,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(color: brand.withValues(alpha: wave.clamp(0.0, 1.0)), width: 2),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// The live dot, breathing (spec §3.2): a soft halo swells and fades for 800 ms, then rests
/// 800 ms (one [BBMotion.pulse]), and repeats. Solid and still under Reduce Motion or when
/// [breathing] is false. Decorative: the caller carries the meaning in text.
class BBLiveDot extends StatefulWidget {
  const BBLiveDot({super.key, required this.color, this.size = 12, this.breathing = true});

  final Color color;
  final double size;
  final bool breathing;

  @override
  State<BBLiveDot> createState() => _BBLiveDotState();
}

class _BBLiveDotState extends State<BBLiveDot> with SingleTickerProviderStateMixin {
  late final BBLoop _loop = BBLoop(vsync: this, active: BBMotion.pulse ~/ 2, rest: BBMotion.pulse ~/ 2);
  bool _reduced = false;

  void _sync() => _loop.run(widget.breathing && !_reduced);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = BBMotion.reduced(context);
    _sync();
  }

  @override
  void didUpdateWidget(BBLiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _loop.controller,
            builder: (context, _) {
              final t = _loop.controller.value;
              // Invisible at 0 and at 1: resting and finished look the same.
              return Transform.scale(
                scale: 1 + 1.2 * t,
                child: Opacity(
                  opacity: (0.45 * math.sin(math.pi * t)).clamp(0.0, 1.0),
                  child: SizedBox.square(
                    dimension: widget.size * 0.66,
                    child: DecoratedBox(decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
                  ),
                ),
              );
            },
          ),
          BBGlyph(BBGlyphKind.liveDot, size: widget.size, color: widget.color),
        ],
      ),
    );
  }
}

/// A soft ring that spreads from the centre and fades, [rings] times ([BBMotion.pulse] each),
/// then is gone: the map's "you are here" ping after My location (spec §3.2). Nothing under
/// Reduce Motion. Decorative and untouchable.
class BBPing extends StatefulWidget {
  const BBPing({super.key, required this.color, this.size = 96, this.rings = 2});

  final Color color;
  final double size;
  final int rings;

  static const ringKey = ValueKey('bb-ping-ring');

  @override
  State<BBPing> createState() => _BBPingState();
}

class _BBPingState extends State<BBPing> with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(vsync: this, duration: BBMotion.pulse);
  bool _started = false;
  bool _done = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = BBMotion.reduced(context);
    if (_reduced) {
      // Reduce Motion (now or turned on mid-ping): stop the rings; build shows nothing.
      _ring.stop();
      _ring.value = 0;
      return;
    }
    if (_started) return;
    _started = true;
    _ring.repeat(count: widget.rings).whenCompleteOrCancel(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced || _done) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _ring,
            builder: (context, _) {
              final t = _ring.value;
              return Center(
                child: Transform.scale(
                  key: BBPing.ringKey,
                  scale: 0.15 + 0.85 * t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.color.withValues(alpha: 0.6 * (1 - t)), width: 3),
                    ),
                    child: SizedBox.square(dimension: widget.size),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

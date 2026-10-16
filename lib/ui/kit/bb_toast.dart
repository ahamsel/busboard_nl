import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Floating message above the bottom safe area (replaces SnackBar). Only one is
/// visible at a time; a new one replaces the current one.
abstract final class BBToast {
  static const cardKey = ValueKey('bb-toast-card');

  static OverlayEntry? _current;

  /// [announce] also tells screen readers now, for a message that answers a tap (a live region alone is not read
  /// out by VoiceOver).
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    bool announce = false,
  }) {
    _dismissCurrent();
    if (announce) {
      unawaited(SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context)));
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        duration: duration,
        announce: announce,
        onDone: () {
          if (identical(_current, entry)) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  static void _dismissCurrent() {
    final current = _current;
    _current = null;
    if (current != null && current.mounted) current.remove();
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.duration,
    required this.announce,
    required this.onDone,
  });

  final String message;
  final Duration duration;

  /// Already announced by [BBToast.show]: not a live region too, or TalkBack reads it twice.
  final bool announce;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);
  late final CurvedAnimation _rise =
      CurvedAnimation(parent: _anim, curve: BBMotion.emphasisCurve, reverseCurve: BBMotion.curve);
  // Opacity must stay within 0..1, so it doesn't follow the spring's overshoot.
  late final CurvedAnimation _fade = CurvedAnimation(parent: _anim, curve: BBMotion.curve);
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _anim.reverse();
      widget.onDone();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honours reduce-motion: a zero duration makes forward()/reverse() complete
    // immediately. The duration must be set before the first forward().
    _anim.duration = BBMotion.of(context, BBMotion.emphasis);
    _anim.reverseDuration = BBMotion.of(context, BBMotion.standard);
    if (!_started) {
      _started = true;
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rise.dispose();
    _fade.dispose();
    _anim.dispose();
    super.dispose();
  }

  /// The inverse card: `ink` with the float shadow. Not the dark top-edge highlight, which is white at 8% and so
  /// cannot be seen on the near-white `ink`.
  BoxDecoration _card(BBTokens bb) {
    final floating = bb.floating(radius: BBRadius.card, color: bb.colors.ink);
    return BoxDecoration(color: floating.color, borderRadius: floating.borderRadius, boxShadow: floating.boxShadow);
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Positioned(
      left: BBSpace.l,
      right: BBSpace.l,
      // Just above the safe area, or above the keyboard when that is taller.
      bottom: math.max(
            MediaQuery.paddingOf(context).bottom + BBSpace.l,
            MediaQuery.viewInsetsOf(context).bottom,
          ) +
          BBSpace.s,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(_rise),
          child: Semantics(
            liveRegion: !widget.announce,
            child: Container(
              key: BBToast.cardKey,
              padding: const EdgeInsets.symmetric(horizontal: BBSpace.l, vertical: BBSpace.m),
              decoration: _card(bb),
              child: Text(widget.message, style: bb.text.label.copyWith(color: bb.colors.bg)),
            ),
          ),
        ),
      ),
    );
  }
}

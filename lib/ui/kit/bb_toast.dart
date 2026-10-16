import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'bb_nav_bar.dart';
import 'tokens.dart';

/// Floating message above the nav bar where it is shown, else above the bottom
/// safe area (replaces SnackBar). Only one is visible at a time; a new one
/// replaces the current one.
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
    final reserveNavBar = BBNavBarScope.isPresent(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        duration: duration,
        reserveNavBar: reserveNavBar,
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
    required this.reserveNavBar,
    required this.onDone,
  });

  final String message;
  final Duration duration;
  final bool reserveNavBar;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);
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
    final d = BBMotion.of(context, BBMotion.standard);
    _anim.duration = d;
    _anim.reverseDuration = d;
    if (!_started) {
      _started = true;
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final curved = CurvedAnimation(parent: _anim, curve: BBMotion.curve);
    return Positioned(
      left: BBSpace.l,
      right: BBSpace.l,
      // Above the nav bar where it is shown (else just above the safe area),
      // or above the keyboard when that is taller.
      bottom: math.max(
            widget.reserveNavBar
                ? BBNavBar.reservedHeight(context)
                : MediaQuery.paddingOf(context).bottom + BBSpace.l,
            MediaQuery.viewInsetsOf(context).bottom,
          ) +
          BBSpace.s,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(curved),
          child: Semantics(
            liveRegion: true,
            child: Container(
              key: BBToast.cardKey,
              padding: const EdgeInsets.symmetric(horizontal: BBSpace.l, vertical: BBSpace.m),
              decoration: bb.floating(radius: BBRadius.card).copyWith(color: bb.colors.ink),
              child: Text(widget.message, style: bb.text.label.copyWith(color: bb.colors.bg)),
            ),
          ),
        ),
      ),
    );
  }
}

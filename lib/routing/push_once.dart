import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Pushes a page for [PushOnce]'s child: once per burst of taps. [then] runs only for a push that happens (another
/// page pushed over it, say).
typedef PushOnceCallback = void Function(String location, {Object? extra, VoidCallback? then});

/// Opens a page at most once for a quick double tap. Both taps land before the next frame shows the page (or while it
/// slides in over this one), so each would push it and the rider would have to go back twice.
///
/// Taps are ignored while the page this pushed is still open. They work again once it is popped, or once this page
/// shows again however it went: uncovered (a link replaced the stack) or its tab back in front. A guard that never
/// reset would leave the control dead, so both ways count.
class PushOnce extends StatefulWidget {
  const PushOnce({super.key, required this.builder});

  /// Builds the control; it calls `push` in place of `context.push`.
  final Widget Function(BuildContext context, PushOnceCallback push) builder;

  @override
  State<PushOnce> createState() => _PushOnceState();
}

class _PushOnceState extends State<PushOnce> {
  /// The page this pushed is still open.
  bool _open = false;

  /// This page was covered (its route no longer current) or hidden (offstage, or its tab behind another).
  bool _covered = false;

  void _push(String location, {Object? extra, VoidCallback? then}) {
    if (_open) return;
    _open = true;
    unawaited(context.push<Object?>(location, extra: extra).whenComplete(() => _open = false));
    then?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = (ModalRoute.isCurrentOf(context) ?? true) && TickerMode.valuesOf(context).enabled;
    if (!shown) {
      _covered = true;
    } else if (_covered) {
      _covered = false;
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _push);
}

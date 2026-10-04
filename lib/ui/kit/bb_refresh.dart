import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'bb_route_dots.dart';
import 'tokens.dart';

/// Pull to refresh with BusBoard's route dots (replaces Material's refresh
/// indicator). Pull past [triggerDistance] (one haptic tick) and
/// release: [onRefresh] runs while the dots hop in a small floating pill.
/// Screen readers get a [refreshAction] on the list and hear "Refreshing",
/// then "Updated". The child must overscroll at the top: the app's bouncing
/// scroll behaviour with AlwaysScrollableScrollPhysics.
class BBRefresh extends StatefulWidget {
  const BBRefresh({super.key, required this.onRefresh, required this.child, this.semanticLabel});

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Names the screen-reader focus stop that carries the "Refresh" action
  /// (e.g. "Departures"), so the action is not announced on an unlabelled node.
  final String? semanticLabel;

  static const double triggerDistance = 72;
  static const CustomSemanticsAction refreshAction = CustomSemanticsAction(label: 'Refresh');

  @override
  State<BBRefresh> createState() => _BBRefreshState();
}

class _BBRefreshState extends State<BBRefresh> {
  double _pull = 0;
  bool _armed = false;
  bool _refreshing = false;
  String _announcement = '';
  Timer? _clearAnnouncement;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final overscroll = (n.metrics.minScrollExtent - n.metrics.pixels).clamp(0.0, double.infinity);
    final dragging = (n is ScrollUpdateNotification && n.dragDetails != null) ||
        (n is OverscrollNotification && n.dragDetails != null);
    if (!_refreshing) {
      if (dragging) {
        if (!_armed && overscroll >= BBRefresh.triggerDistance) {
          _armed = true;
          HapticFeedback.selectionClick();
        } else if (_armed && overscroll < BBRefresh.triggerDistance) {
          _armed = false; // Pulled back above the line: cancelled.
        }
      } else if (_armed && (n is ScrollUpdateNotification || n is ScrollEndNotification)) {
        _armed = false; // Released past the line.
        unawaited(_refresh());
      }
    }
    if (overscroll != _pull) setState(() => _pull = overscroll);
    return false;
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _clearAnnouncement?.cancel();
    setState(() {
      _refreshing = true;
      _announcement = 'Refreshing';
    });
    var failed = false;
    try {
      await widget.onRefresh();
    } catch (error, stack) {
      failed = true;
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'BBRefresh'));
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _announcement = failed ? "Couldn't refresh" : 'Updated';
        });
        _clearAnnouncement = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _announcement = '');
        });
      }
    }
  }

  @override
  void dispose() {
    _clearAnnouncement?.cancel();
    super.dispose();
  }

  Widget _indicator(BuildContext context) {
    final bb = context.bb;
    if (_refreshing) {
      return Padding(
        padding: const EdgeInsets.only(top: BBSpace.s),
        child: Center(
          child: DecoratedBox(
            decoration: bb.floating(radius: BBRadius.sheet),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.s),
              child: BBRouteDots(dotSize: 8),
            ),
          ),
        ),
      );
    }
    if (_pull <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: _pull,
      child: Center(child: BBRouteDots(progress: _pull / BBRefresh.triggerDistance, dotSize: 8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      customSemanticsActions: {BBRefresh.refreshAction: () => unawaited(_refresh())},
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
          Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: _indicator(context))),
          Positioned(
            top: 0,
            left: 0,
            // 1×1, not zero-size: zero-area nodes can be dropped from the tree.
            child: Semantics(liveRegion: true, label: _announcement, child: const SizedBox(width: 1, height: 1)),
          ),
        ],
      ),
    );
  }
}

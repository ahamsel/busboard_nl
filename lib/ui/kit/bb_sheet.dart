import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Draggable bottom sheet with three detents (peek / half / full) and a
/// haptic tick when it settles on one. Place it in a Stack over the content.
class BBSheet extends StatefulWidget {
  const BBSheet({
    super.key,
    required this.slivers,
    required this.peekFraction,
    this.halfFraction = 0.5,
    this.fullFraction = 0.9,
    this.initialFraction,
    this.controller,
  }) : assert(peekFraction > 0 && peekFraction < halfFraction && halfFraction < fullFraction && fullFraction <= 1,
            'BBSheet fractions must satisfy 0 < peek < half < full <= 1');

  final List<Widget> slivers;
  final double peekFraction;
  final double halfFraction;
  final double fullFraction;
  final double? initialFraction;
  final DraggableScrollableController? controller;

  @override
  State<BBSheet> createState() => _BBSheetState();
}

class _BBSheetState extends State<BBSheet> {
  double? _lastDetent;

  bool _onExtent(DraggableScrollableNotification n) {
    for (final detent in [widget.peekFraction, widget.halfFraction, widget.fullFraction]) {
      if ((n.extent - detent).abs() < 0.004) {
        if (_lastDetent != detent) {
          _lastDetent = detent;
          HapticFeedback.selectionClick();
        }
        return false;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final reduce = BBMotion.of(context, BBMotion.sheet) == Duration.zero;
    const radius = BorderRadius.vertical(top: Radius.circular(BBRadius.sheet));
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _onExtent,
      child: DraggableScrollableSheet(
        controller: widget.controller,
        initialChildSize: widget.initialFraction ?? widget.peekFraction,
        minChildSize: widget.peekFraction,
        maxChildSize: widget.fullFraction,
        snap: true,
        snapSizes: [widget.halfFraction],
        // The sheet API rejects Duration.zero, so "reduce motion" uses 1 ms.
        snapAnimationDuration: reduce ? const Duration(milliseconds: 1) : BBMotion.sheet,
        builder: (context, scrollController) => DecoratedBox(
          decoration: bb.floating(borderRadius: radius).copyWith(color: bb.colors.bg),
          child: ClipRRect(
            borderRadius: radius,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: BBSpace.s, bottom: BBSpace.m),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: bb.colors.line, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
                ...widget.slivers,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/widgets.dart';

import 'bb_card.dart';
import 'bb_loop.dart';
import 'tokens.dart';

enum BBSkeletonKind { arrivalRow, alertCard, stopCard, line }

/// Placeholder rows shaped like the content they stand in for, shown while a list first loads.
/// A soft band of light sweeps across the blocks (1 s), rests (0.6 s) and sweeps again (spec
/// §3.2); still under Reduce Motion. Announced once as [label]. [BBSkeletonKind.line] is a bare
/// bar with no card around it, for inside a card that is already on screen.
class BBSkeleton extends StatefulWidget {
  const BBSkeleton({super.key, required this.kind, this.count = 3, this.label = 'Loading'});

  final BBSkeletonKind kind;
  final int count;
  final String label;

  static const shimmerKey = ValueKey('bb-skeleton-shimmer');

  @override
  State<BBSkeleton> createState() => _BBSkeletonState();
}

/// Moves a gradient sideways by [dx] of the painted width.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);

  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * dx, 0, 0);
}

class _BBSkeletonState extends State<BBSkeleton> with SingleTickerProviderStateMixin {
  late final BBLoop _shimmer = BBLoop(
    vsync: this,
    active: const Duration(milliseconds: 1000),
    rest: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shimmer.run(!BBMotion.reduced(context));
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  /// Sweeps a lighter band across [blocks], painting only where the blocks are.
  Widget _shine(Widget blocks) {
    final bb = context.bb;
    final block = bb.colors.skeleton;
    final light = bb.isDark ? const Color(0xFFFFFFFF) : bb.colors.surface;
    final shine = Color.lerp(block, light, bb.isDark ? 0.12 : 0.7)!;
    return AnimatedBuilder(
      animation: _shimmer.controller,
      child: blocks,
      builder: (context, child) => ShaderMask(
        key: BBSkeleton.shimmerKey,
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          colors: [block, shine, block],
          stops: const [0.35, 0.5, 0.65],
          // The band starts and ends off the blocks, so resting and finished look the same.
          transform: _SlideGradient(-1 + 2 * _shimmer.controller.value),
        ).createShader(rect),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final block = bb.colors.skeleton;

    Widget box(double w, double h, {double r = 4}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(r)),
        );
    Widget bar(double widthFactor, double h) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: box(double.infinity, h),
        );

    Widget item() => switch (widget.kind) {
          BBSkeletonKind.arrivalRow => Row(children: [
              box(40, 40, r: BBRadius.badge),
              const SizedBox(width: BBSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  bar(0.7, 14),
                  const SizedBox(height: BBSpace.s),
                  bar(0.45, 10),
                ]),
              ),
              const SizedBox(width: BBSpace.m),
              box(28, 24, r: 6),
            ]),
          BBSkeletonKind.alertCard => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              box(40, 40, r: BBRadius.badge),
              const SizedBox(width: BBSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  bar(0.8, 14),
                  const SizedBox(height: BBSpace.s),
                  Row(children: [box(48, 18, r: BBRadius.pill), const SizedBox(width: 6), box(26, 18, r: 6)]),
                  const SizedBox(height: BBSpace.s),
                  bar(1, 10),
                  const SizedBox(height: 6),
                  bar(0.6, 10),
                ]),
              ),
            ]),
          BBSkeletonKind.stopCard => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              bar(0.6, 14),
              const SizedBox(height: 6),
              bar(0.35, 10),
              const SizedBox(height: BBSpace.s),
              Row(children: [
                for (var i = 0; i < 3; i++) ...[box(26, 20, r: 6), const SizedBox(width: 6)],
              ]),
            ]),
          BBSkeletonKind.line => const SizedBox.shrink(),
        };

    if (widget.kind == BBSkeletonKind.line) {
      return Semantics(
        container: true,
        liveRegion: true,
        label: widget.label,
        child: ExcludeSemantics(
          child: _shine(Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.count; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == widget.count - 1 ? 0 : BBSpace.s),
                  child: bar(0.6, 14),
                ),
            ],
          )),
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.count; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: BBSpace.s),
                child: Container(
                  key: const ValueKey('bb-skeleton-item'),
                  padding: const EdgeInsets.all(BBSpace.m),
                  decoration: BBSurfaceScope.cardOf(context),
                  // Only the blocks shine, not the card around them.
                  child: _shine(item()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum BBSkeletonKind { arrivalRow, alertCard, stopCard, line }

/// Static placeholder rows shaped like the content they stand in for, shown
/// while a list first loads. No shimmer (reduce-motion safe); announced once
/// as [label]. [BBSkeletonKind.line] is a bare bar with no card around it, for
/// inside a card that is already on screen.
class BBSkeleton extends StatelessWidget {
  const BBSkeleton({super.key, required this.kind, this.count = 3, this.label = 'Loading'});

  final BBSkeletonKind kind;
  final int count;
  final String label;

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

    Widget item() => switch (kind) {
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

    if (kind == BBSkeletonKind.line) {
      return Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : BBSpace.s),
                  child: bar(0.6, 14),
                ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: BBSpace.s),
                child: Container(
                  key: const ValueKey('bb-skeleton-item'),
                  padding: const EdgeInsets.all(BBSpace.m),
                  decoration: bb.card(),
                  child: item(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('shows one placeholder per count and announces a single label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 4, label: 'Loading departures...')));
    expect(find.byKey(const ValueKey('bb-skeleton-item')), findsNWidgets(4));
    expect(find.semantics.byLabel('Loading departures...'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(BBSkeleton)),
      isSemantics(label: 'Loading departures...', isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('every kind lays out at 2x text on a 320 pt screen without overflow', (tester) async {
    for (final kind in BBSkeletonKind.values) {
      await tester.pumpWidget(kitHost(BBSkeleton(kind: kind), width: 320, textScale: 2));
      expect(tester.takeException(), isNull, reason: kind.name);
    }
  });

  testWidgets('the shimmer sweeps for 1 s, then rests 0.6 s with no frames, then sweeps again', (tester) async {
    await tester.pumpWidget(kitHost(const BBSkeleton(kind: BBSkeletonKind.arrivalRow)));
    expect(find.byKey(BBSkeleton.shimmerKey), findsNWidgets(3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue, reason: 'sweeping');
    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.hasRunningAnimations, isFalse, reason: 'resting');
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 650));
    expect(tester.hasRunningAnimations, isTrue, reason: 'the next sweep');
  });

  testWidgets('each shimmer repaints in its own layer, not the whole list', (tester) async {
    await tester.pumpWidget(kitHost(const BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 3)));
    final shimmers = find.byKey(BBSkeleton.shimmerKey);
    expect(shimmers, findsNWidgets(3));
    final bounded = find.descendant(
      of: find.descendant(of: find.byType(BBSkeleton), matching: find.byType(RepaintBoundary)),
      matching: shimmers,
    );
    expect(bounded, findsNWidgets(3));
    await tester.pumpWidget(kitHost(const BBSkeleton(kind: BBSkeletonKind.line, count: 2)));
    expect(
      find.descendant(
        of: find.descendant(of: find.byType(BBSkeleton), matching: find.byType(RepaintBoundary)),
        matching: find.byKey(BBSkeleton.shimmerKey),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Reduce Motion: still blocks, no shimmer', (tester) async {
    for (final kind in BBSkeletonKind.values) {
      await tester.pumpWidget(kitHost(Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: BBSkeleton(kind: kind),
        ),
      )));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isFalse, reason: kind.name);
    }
  });
}

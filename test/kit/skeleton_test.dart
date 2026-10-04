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

  testWidgets('every kind lays out at 2x text on a 320 pt screen without overflow and without animating', (tester) async {
    for (final kind in BBSkeletonKind.values) {
      await tester.pumpWidget(kitHost(BBSkeleton(kind: kind), width: 320, textScale: 2));
      expect(tester.takeException(), isNull, reason: kind.name);
      expect(tester.hasRunningAnimations, isFalse, reason: kind.name);
    }
  });
}

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Matrix4 _dot(WidgetTester tester, int i) =>
    tester.widget<Transform>(find.byKey(ValueKey('bb-route-dot-$i'))).transform;

double _scale(WidgetTester tester, int i) => _dot(tester, i).getMaxScaleOnAxis();

void main() {
  testWidgets('pull progress grows the dots in turn', (tester) async {
    await tester.pumpWidget(kitHost(const Center(child: BBRouteDots(progress: 0))));
    for (var i = 0; i < 3; i++) {
      expect(_scale(tester, i), closeTo(0.4, 0.001));
    }

    await tester.pumpWidget(kitHost(const Center(child: BBRouteDots(progress: 0.5))));
    expect(_scale(tester, 0), closeTo(1.0, 0.001));
    expect(_scale(tester, 1), closeTo(0.7, 0.001));
    expect(_scale(tester, 2), closeTo(0.4, 0.001));

    await tester.pumpWidget(kitHost(const Center(child: BBRouteDots(progress: 1))));
    for (var i = 0; i < 3; i++) {
      expect(_scale(tester, i), closeTo(1.0, 0.001));
    }
  });

  testWidgets('without progress the dots hop', (tester) async {
    await tester.pumpWidget(kitHost(const Center(child: BBRouteDots())));
    final before = _dot(tester, 0).clone();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_dot(tester, 0), isNot(equals(before)));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('reduce motion shows still, filled dots and runs no animation', (tester) async {
    await tester.pumpWidget(kitHost(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Center(child: BBRouteDots()),
    )));
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 3; i++) {
      expect(_scale(tester, i), closeTo(1.0, 0.001));
      expect(_dot(tester, i).getTranslation().y, 0);
    }
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('BBLoading no longer uses a Material spinner', (tester) async {
    await tester.pumpWidget(kitHost(const BBLoading(label: 'Loading schedule data...')));
    expect(find.byType(BBRouteDots), findsOneWidget);
    expect(find.text('Loading schedule data...'), findsOneWidget);
  });
}

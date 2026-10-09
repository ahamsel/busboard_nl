import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

void main() {
  final now = DateTime(testDay.year, testDay.month, testDay.day, 8, 1);

  testWidgets('/plan/journey without a journey (a deep link, a restored route) opens the planner', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/plan/journey');
    expect(tester.takeException(), isNull);
    expect(find.text('Plan a trip'), findsOneWidget);
    expect(find.text('Your trip'), findsNothing);
  });
}

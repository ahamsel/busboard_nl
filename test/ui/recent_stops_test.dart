import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/recent_stops_provider.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

void main() {
  testWidgets("a stop's card on the map counts as viewing the stop (spec 2026-10-15 §3)", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: DateTime(2026, 10, 12, 13));
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    c.read(homeSheetProvider.notifier).open(const StopSheet('B'));
    await tester.pumpAndSettle();
    c.read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    expect(c.read(recentStopsProvider).value, ['C', 'B']);
  });
}

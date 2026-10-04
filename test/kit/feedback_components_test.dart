import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Widget _launcher(void Function(BuildContext) onPressed) {
  return kitHost(Builder(
    builder: (context) => BBButton(label: 'go', onPressed: () => onPressed(context)),
  ));
}

void main() {
  testWidgets('toast appears, announces, then disappears', (tester) async {
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'Bus 2134 is no longer reporting')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Bus 2134 is no longer reporting'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Bus 2134 is no longer reporting'), findsNothing);
  });

  testWidgets('a second toast replaces the first without errors', (tester) async {
    var n = 0;
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'toast ${++n}')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('toast 1'), findsNothing);
    expect(find.text('toast 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('toast survives its launching screen being removed', (tester) async {
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'bye')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(kitHost(const Text('other screen')));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('toast honours reduce motion: fully visible on first frame', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'instant')));
    await tester.tap(find.text('go'));
    await tester.pump();
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: find.text('instant'), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 1.0);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('instant'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog returns the tapped action value', (tester) async {
    String? result;
    await tester.pumpWidget(_launcher((c) async {
      result = await BBDialog.show<String>(c, title: 'Change stop?', message: 'Your board will switch.', actions: const [
        BBDialogAction(label: 'Cancel', value: 'no'),
        BBDialogAction(label: 'Change', value: 'yes', primary: true),
      ]);
    }));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Change stop?'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(result, 'yes');
    expect(find.text('Change stop?'), findsNothing);
  });

  testWidgets('pull to refresh calls onRefresh', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(kitHost(SizedBox(
      height: 600,
      child: BBRefresh(
        onRefresh: () async => refreshed++,
        child: ListView(children: const [SizedBox(height: 100, child: Text('row'))]),
      ),
    )));
    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });
}

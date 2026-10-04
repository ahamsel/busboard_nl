import 'dart:async';

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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

  testWidgets('toast stays above the on-screen keyboard', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'above keys')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    final toastBottom = tester.getBottomLeft(find.text('above keys')).dy;
    expect(toastBottom, lessThanOrEqualTo(800 - 300), reason: 'toast bottom at $toastBottom is under the keyboard');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('outside the tab shell the toast sits just above the bottom safe area', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'no bar here')));
    await tester.tap(find.text('go'));
    await tester.pump(); // first frame: inserts the overlay and starts the slide
    await tester.pump(const Duration(milliseconds: 250));
    final bottom = tester.getRect(find.byKey(BBToast.cardKey)).bottom;
    expect(bottom, closeTo(800 - 34 - BBSpace.l - BBSpace.s, 0.5));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('inside the tab shell the toast clears the nav bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late double reserved;
    await tester.pumpWidget(kitHost(BBNavBarScope(
      child: Builder(builder: (c) {
        reserved = BBNavBar.reservedHeight(c);
        return BBButton(label: 'go', onPressed: () => BBToast.show(c, 'above the bar'));
      }),
    )));
    await tester.tap(find.text('go'));
    await tester.pump(); // first frame: inserts the overlay and starts the slide
    await tester.pump(const Duration(milliseconds: 250));
    final bottom = tester.getRect(find.byKey(BBToast.cardKey)).bottom;
    expect(bottom, closeTo(800 - reserved - BBSpace.s, 0.5));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
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

  testWidgets('dialog fits a 320x568 phone at text scale 2.0 with actions reachable', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const message = 'Your board will switch to the new stop and your saved favourites stay as they are. '
        'You can change it back at any time from the stop picker on the board screen.';
    await tester.pumpWidget(kitHost(
      Builder(
        builder: (context) => BBButton(
          label: 'go',
          onPressed: () => BBDialog.show<String>(context, title: 'Change stop?', message: message, actions: const [
            BBDialogAction(label: 'Cancel', value: 'no'),
            BBDialogAction(label: 'Change', value: 'yes', primary: true),
          ]),
        ),
      ),
      textScale: 2.0,
      width: 320,
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(find.text('Change').hitTestable(), findsOneWidget);
  });

  testWidgets('dialog names its route for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_launcher((c) => BBDialog.show<String>(c, title: 'Change stop?', actions: const [
          BBDialogAction(label: 'OK', value: 'ok'),
        ])));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Change stop?').first),
      isSemantics(label: 'Change stop?', namesRoute: true),
    );
    handle.dispose();
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

  Widget refreshHost(Future<void> Function() onRefresh, {String? semanticLabel}) => kitHost(SizedBox(
        height: 600,
        child: BBRefresh(
          onRefresh: onRefresh,
          semanticLabel: semanticLabel,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 100, child: Text('row'))],
          ),
        ),
      ));

  testWidgets('the Refresh action sits on a node labelled with semanticLabel', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(refreshHost(() async {}, semanticLabel: 'Departures'));
    final id = CustomSemanticsAction.getIdentifier(BBRefresh.refreshAction);
    final node = find.semantics.byPredicate((n) => n.getSemanticsData().customSemanticsActionIds?.contains(id) ?? false);
    expect(node, findsOneWidget);
    expect(node, isSemantics(label: 'Departures', customActions: [BBRefresh.refreshAction]));
    handle.dispose();
  });

  testWidgets('pulling past the trigger ticks once, and a short pull does not refresh', (tester) async {
    var ticks = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') ticks++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    var refreshed = 0;
    await tester.pumpWidget(refreshHost(() async => refreshed++));

    await tester.drag(find.text('row'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(refreshed, 0);
    expect(ticks, 0);

    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    expect(ticks, 1);
  });

  testWidgets('screen readers can refresh with the Refresh action', (tester) async {
    final handle = tester.ensureSemantics();
    final done = Completer<void>();
    var refreshed = 0;
    await tester.pumpWidget(refreshHost(() {
      refreshed++;
      return done.future;
    }));
    final id = CustomSemanticsAction.getIdentifier(BBRefresh.refreshAction);
    tester.semantics.customAction(
      find.semantics.byPredicate((n) => n.getSemanticsData().customSemanticsActionIds?.contains(id) ?? false),
      BBRefresh.refreshAction,
    );
    await tester.pump();
    expect(refreshed, 1);
    expect(find.semantics.byPredicate((n) => n.flagsCollection.isLiveRegion && n.label == 'Refreshing'), findsOneWidget);
    done.complete();
    await tester.pump();
    expect(find.semantics.byPredicate((n) => n.flagsCollection.isLiveRegion && n.label == 'Updated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    handle.dispose();
  });

  testWidgets('a pull during a refresh does not start another', (tester) async {
    final done = Completer<void>();
    var refreshed = 0;
    await tester.pumpWidget(refreshHost(() {
      refreshed++;
      return done.future;
    }));
    // The hopping dots loop while refreshing, so pump fixed durations here:
    // pumpAndSettle would never settle.
    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pump(const Duration(seconds: 1));
    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, 1);
    expect(find.byType(BBRouteDots), findsOneWidget);
    done.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(BBRouteDots), findsNothing);
  });

  testWidgets('a failing refresh ends the indicator and reports once', (tester) async {
    final handle = tester.ensureSemantics();
    var calls = 0;
    await tester.pumpWidget(refreshHost(() async {
      calls++;
      throw StateError('offline');
    }));
    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(find.byType(BBRouteDots), findsNothing);
    expect(find.semantics.byPredicate((n) => n.flagsCollection.isLiveRegion && n.label == "Couldn't refresh"), findsOneWidget);
    expect(find.semantics.byPredicate((n) => n.flagsCollection.isLiveRegion && n.label == 'Updated'), findsNothing);

    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(calls, 2);
    handle.dispose();
  });
}

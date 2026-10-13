import 'package:busboard_nl/ui/kit/bb_loop.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

/// [child] with the OS Reduce Motion setting on.
Widget _reduced(Widget child) => Builder(
      builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child),
    );

/// [child] with Reduce Motion following [reduce], so a test can turn it on or off mid-animation.
Widget _reducedWhen(ValueNotifier<bool> reduce, Widget child) => ValueListenableBuilder<bool>(
      valueListenable: reduce,
      builder: (context, on, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: on), child: child!),
      child: child,
    );

/// [inner] under a [RepaintBoundary] that is itself inside [owner]: the owner's animation repaints only that layer,
/// not the sheet or page the owner sits in.
Finder _boundedIn(Type owner, Finder inner) =>
    find.descendant(of: find.descendant(of: find.byType(owner), matching: find.byType(RepaintBoundary)), matching: inner);

void main() {
  group('BBRollingText', () {
    testWidgets('rolls the old value out and the new one in, then shows only the new one', (tester) async {
      Widget host(String t) => kitHost(Center(child: BBRollingText(t, style: const TextStyle(fontSize: 26))));
      await tester.pumpWidget(host('7'));
      await tester.pumpWidget(host('6'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('7'), findsOneWidget, reason: 'mid-roll, both show');
      expect(find.text('6'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('7'), findsNothing);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('mid-roll, a merged row announces only the new value', (tester) async {
      final handle = tester.ensureSemantics();
      Widget host(String t) => kitHost(
            Center(child: MergeSemantics(child: BBRollingText(t, style: const TextStyle(fontSize: 26)))),
          );
      await tester.pumpWidget(host('7'));
      await tester.pumpWidget(host('6'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('7'), findsOneWidget, reason: 'mid-roll, both show');
      expect(tester.getSemantics(find.byType(MergeSemantics)).label, '6');
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.byType(MergeSemantics)).label, '6');
      handle.dispose();
    });

    testWidgets('Reduce Motion: the new value replaces the old at once', (tester) async {
      Widget host(String t) => kitHost(_reduced(Center(child: BBRollingText(t, style: const TextStyle(fontSize: 26)))));
      await tester.pumpWidget(host('7'));
      await tester.pumpWidget(host('6'));
      expect(find.text('7'), findsNothing);
      expect(find.text('6'), findsOneWidget);
    });
  });

  group('BBNowPulse', () {
    double scaleOf(WidgetTester tester) =>
        tester.widget<Transform>(find.descendant(of: find.byType(BBNowPulse), matching: find.byType(Transform)).first)
            .transform
            .getMaxScaleOnAxis();

    testWidgets('the pulse repaints in its own layer, not the whole sheet', (tester) async {
      await tester.pumpWidget(kitHost(const BBNowPulse(active: false, child: Text('row'))));
      expect(_boundedIn(BBNowPulse, find.byType(Transform)), findsOneWidget);
    });

    testWidgets('pulses once when the row becomes Now, peaking at 1.08', (tester) async {
      Widget host(bool now) => kitHost(BBNowPulse(active: now, child: const SizedBox(height: 60, child: Text('row'))));
      await tester.pumpWidget(host(false));
      expect(scaleOf(tester), 1);
      await tester.pumpWidget(host(true));
      await tester.pump(); // first tick
      await tester.pump(const Duration(milliseconds: 300)); // half of nowPulse
      expect(scaleOf(tester), closeTo(1.08, 0.005));
      await tester.pumpAndSettle();
      expect(scaleOf(tester), 1);
      await tester.pumpWidget(host(true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scaleOf(tester), 1, reason: 'staying Now does not pulse again');
    });

    testWidgets('a row that is already Now when it first shows does not pulse', (tester) async {
      await tester.pumpWidget(kitHost(const BBNowPulse(active: true, child: Text('row'))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scaleOf(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('Reduce Motion: no pulse', (tester) async {
      Widget host(bool now) => kitHost(_reduced(BBNowPulse(active: now, child: const Text('row'))));
      await tester.pumpWidget(host(false));
      await tester.pumpWidget(host(true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scaleOf(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('Reduce Motion switched on mid-pulse stops it at rest', (tester) async {
      final reduce = ValueNotifier(false);
      addTearDown(reduce.dispose);
      Widget host(bool now) => kitHost(_reducedWhen(reduce, BBNowPulse(active: now, child: const Text('row'))));
      await tester.pumpWidget(host(false));
      await tester.pumpWidget(host(true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      expect(scaleOf(tester), greaterThan(1));
      reduce.value = true;
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(scaleOf(tester), 1);
    });
  });

  group('BBLiveDot', () {
    testWidgets('the breathing halo repaints in its own layer, not the whole sheet', (tester) async {
      await tester.pumpWidget(kitHost(Center(child: BBLiveDot(color: BBColors.light.live))));
      expect(_boundedIn(BBLiveDot, find.byType(Transform)), findsOneWidget);
    });

    testWidgets('breathes for 800 ms, rests 800 ms with no frames, then breathes again', (tester) async {
      await tester.pumpWidget(kitHost(Center(child: BBLiveDot(color: BBColors.light.live))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue, reason: 'breathing');
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.hasRunningAnimations, isFalse, reason: 'resting');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'a rest schedules no frames');
      await tester.pump(const Duration(milliseconds: 850));
      expect(tester.hasRunningAnimations, isTrue, reason: 'the next breath');
    });

    testWidgets('pumpAndSettle returns on a live dot (the loop rests)', (tester) async {
      await tester.pumpWidget(kitHost(Center(child: BBLiveDot(color: BBColors.light.live))));
      await tester.pumpAndSettle();
      expect(find.byType(BBLiveDot), findsOneWidget);
    });

    testWidgets('Reduce Motion, or breathing off: a solid dot and no loop', (tester) async {
      await tester.pumpWidget(kitHost(_reduced(Center(child: BBLiveDot(color: BBColors.light.live)))));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(kitHost(Center(child: BBLiveDot(color: BBColors.light.muted, breathing: false))));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(BBGlyph), findsOneWidget, reason: 'the dot itself still shows');
    });

    // Review Focus 5: a never-ending loop must leave frame-free rests and must stop for good when
    // motion is turned off, or any screen with live data would never settle.
    testWidgets('keeps cycling through many rests, and every rest is frame-free', (tester) async {
      await tester.pumpWidget(kitHost(Center(child: BBLiveDot(color: BBColors.light.live))));
      for (var cycle = 0; cycle < 5; cycle++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.hasRunningAnimations, isTrue, reason: 'cycle $cycle breathing');
        await tester.pumpAndSettle(); // returns at the start of the rest
        expect(tester.binding.hasScheduledFrame, isFalse, reason: 'cycle $cycle resting');
        // Halfway through the rest it is still resting (a zero-length rest would already be breathing).
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.hasRunningAnimations, isFalse, reason: 'cycle $cycle mid-rest');
        expect(tester.binding.hasScheduledFrame, isFalse, reason: 'cycle $cycle mid-rest');
        await tester.pump(const Duration(milliseconds: 450)); // the rest ends, the next breath starts
      }
    });

    testWidgets('Reduce Motion switched on while breathing stops the loop for good', (tester) async {
      final reduce = ValueNotifier(false);
      addTearDown(reduce.dispose);
      await tester.pumpWidget(kitHost(ValueListenableBuilder<bool>(
        valueListenable: reduce,
        builder: (context, on, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: on), child: child!),
        child: Center(child: BBLiveDot(color: BBColors.light.live)),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      reduce.value = true;
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse, reason: 'stopped mid-breath');
      await tester.pump(const Duration(seconds: 5));
      expect(tester.hasRunningAnimations, isFalse, reason: 'no later breath');
      expect(tester.binding.hasScheduledFrame, isFalse);
      reduce.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue, reason: 'motion allowed again, the loop resumes');
    });

    testWidgets('breathing turned off during a rest cancels the pending breath', (tester) async {
      Widget host(bool breathing) =>
          kitHost(Center(child: BBLiveDot(color: BBColors.light.live, breathing: breathing)));
      await tester.pumpWidget(host(true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 800)); // finished; the rest timer is pending
      await tester.pumpWidget(host(false));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.hasRunningAnimations, isFalse, reason: 'the rest timer must not restart the loop');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('BBLoop', () {
    testWidgets('stopping it leaves it at 0 and a pending rest timer never restarts it', (tester) async {
      const ms100 = Duration(milliseconds: 100);
      final loop = BBLoop(vsync: const TestVSync(), active: ms100, rest: ms100);
      loop.run(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150)); // done; resting
      expect(loop.controller.isAnimating, isFalse);
      loop.run(false);
      expect(loop.isRunning, isFalse);
      expect(loop.controller.value, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(loop.controller.isAnimating, isFalse);
      expect(loop.controller.value, 0);
      loop.run(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(loop.controller.isAnimating, isTrue, reason: 'it can be started again');
      loop.dispose(); // before the test ends: no live ticker may outlive it
    });
  });

  group('BBPing', () {
    testWidgets('rings twice (1.6 s each), then is gone', (tester) async {
      await tester.pumpWidget(kitHost(Center(child: BBPing(color: BBColors.light.brand))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(BBPing.ringKey), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.byKey(BBPing.ringKey), findsOneWidget, reason: 'second ring');
      await tester.pumpAndSettle();
      expect(find.byKey(BBPing.ringKey), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('Reduce Motion switched on mid-ping stops it and removes the ring', (tester) async {
      final reduce = ValueNotifier(false);
      addTearDown(reduce.dispose);
      await tester.pumpWidget(kitHost(_reducedWhen(reduce, Center(child: BBPing(color: BBColors.light.brand)))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(BBPing.ringKey), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
      reduce.value = true;
      await tester.pump();
      expect(find.byKey(BBPing.ringKey), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('Reduce Motion: no ping at all', (tester) async {
      await tester.pumpWidget(kitHost(_reduced(Center(child: BBPing(color: BBColors.light.brand)))));
      await tester.pump();
      expect(find.byKey(BBPing.ringKey), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

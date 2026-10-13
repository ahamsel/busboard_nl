import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker, CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast_test.dart' show contrast;
import 'kit_test_helpers.dart';

// Wednesday 7 October 2026, 08:01: "now".
final _now = DateTime(2026, 10, 7, 8, 1);

/// Opens the picker from a button and returns a handle on the result.
class _Opened {
  DateTime? result;
  bool closed = false;
}

Future<_Opened> _open(
  WidgetTester tester, {
  DateTime? initial,
  DateTime? first,
  DateTime? last,
  bool use24h = true,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  String title = 'Leave by',
}) async {
  final opened = _Opened();
  await tester.pumpWidget(kitHost(
    Builder(
      builder: (context) => BBButton(
        label: 'Open',
        onPressed: () async {
          opened.result = await showBBWhenPicker(
            context,
            title: title,
            initial: initial ?? DateTime(2026, 10, 7, 8, 35),
            first: first ?? _now,
            last: last ?? DateTime(2026, 10, 10),
            use24h: use24h,
          );
          opened.closed = true;
        },
      ),
    ),
    textScale: textScale,
    brightness: brightness,
    use24h: use24h,
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return opened;
}

/// Turns [wheel] to [item], as a finger would land it.
Future<void> _turn(WidgetTester tester, Key wheel, int item) async {
  final w = tester.widget<ListWheelScrollView>(find.byKey(wheel));
  (w.controller! as FixedExtentScrollController).jumpToItem(item);
  await tester.pumpAndSettle();
}

/// Taps [finder] after scrolling it into view (the sheet scrolls when it is taller than the screen).
Future<void> _tapIn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _confirmLabel(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(BBWhenPicker.confirmKey), matching: find.byType(Text)))
    .map((t) => t.data)
    .join();

Future<void> _confirm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(BBWhenPicker.confirmKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(BBWhenPicker.confirmKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('day chips run from today to the last day: Today, Tomorrow, then weekdays', (tester) async {
    await _open(tester);
    for (final (i, label) in [(0, 'Today'), (1, 'Tomorrow'), (2, 'Fri'), (3, 'Sat')]) {
      expect(find.descendant(of: find.byKey(BBWhenPicker.dayKey(i)), matching: find.text(label)), findsOneWidget);
    }
    expect(find.byKey(BBWhenPicker.dayKey(4)), findsNothing, reason: 'nothing after last');
  });

  testWidgets('beyond a week, chips name the date too', (tester) async {
    await _open(tester, last: DateTime(2026, 10, 20));
    await tester.scrollUntilVisible(find.byKey(BBWhenPicker.dayKey(8)), 200,
        scrollable: find.descendant(of: find.byKey(BBWhenPicker.sheetKey), matching: find.byType(Scrollable)).at(1));
    expect(find.descendant(of: find.byKey(BBWhenPicker.dayKey(8)), matching: find.text('Thu 15')), findsOneWidget);
  });

  testWidgets('the wheels set the time, and every minute is reachable', (tester) async {
    // 09:xx is all after "now" (08:01), so no minute reads as past.
    final opened = await _open(tester, initial: DateTime(2026, 10, 7, 9, 35));
    expect(_confirmLabel(tester), 'Set 09:35 today');
    for (var m = 0; m < 60; m++) {
      await _turn(tester, BBWhenPicker.minuteWheelKey, m);
      expect(_confirmLabel(tester), 'Set 09:${m.toString().padLeft(2, '0')} today', reason: 'minute $m');
    }
    await _turn(tester, BBWhenPicker.hourWheelKey, 13);
    await _turn(tester, BBWhenPicker.minuteWheelKey, 20);
    expect(_confirmLabel(tester), 'Set 13:20 today');
    await _confirm(tester);
    expect(opened.result, DateTime(2026, 10, 7, 13, 20));
  });

  testWidgets('a day chip moves the day, keeping the time', (tester) async {
    final opened = await _open(tester);
    await _tapIn(tester, find.byKey(BBWhenPicker.dayKey(2)));
    expect(_confirmLabel(tester), 'Set 08:35 Friday');
    await _confirm(tester);
    expect(opened.result, DateTime(2026, 10, 9, 8, 35));
  });

  testWidgets('12-hour mode: the wheel runs 12, 1 … 11 and AM/PM; 12 AM is midnight and 12 PM is noon', (tester) async {
    final opened = await _open(tester, use24h: false);
    final hours = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.hourWheelKey));
    expect((hours.childDelegate as ListWheelChildBuilderDelegate).childCount, 12);
    expect(find.byKey(BBWhenPicker.periodWheelKey), findsOneWidget);
    expect(_confirmLabel(tester), 'Set 8:35 AM today');
    expect((hours.controller! as FixedExtentScrollController).selectedItem, 8, reason: '8 AM is item 8');

    await _turn(tester, BBWhenPicker.hourWheelKey, 1); // "1"
    await _turn(tester, BBWhenPicker.periodWheelKey, 1); // PM
    await _turn(tester, BBWhenPicker.minuteWheelKey, 20);
    expect(_confirmLabel(tester), 'Set 1:20 PM today');

    await _turn(tester, BBWhenPicker.hourWheelKey, 0); // "12", PM: noon
    expect(_confirmLabel(tester), 'Set 12:20 PM today');
    await _tapIn(tester, find.byKey(BBWhenPicker.dayKey(1)));
    await _turn(tester, BBWhenPicker.periodWheelKey, 0); // 12 AM tomorrow: midnight
    expect(_confirmLabel(tester), 'Set 12:20 AM tomorrow');
    await _confirm(tester);
    expect(opened.result, DateTime(2026, 10, 8, 0, 20));
  });

  testWidgets('12-hour mode: the first wheel item is "12", with the last "11" below it', (tester) async {
    await _open(tester, use24h: false);
    final hours = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.hourWheelKey));
    final delegate = hours.childDelegate as ListWheelChildBuilderDelegate;
    String shown(int i) {
      final row = delegate.build(tester.element(find.byKey(BBWhenPicker.hourWheelKey)), i)! as IndexedSemantics;
      return ((row.child! as Center).child! as Text).data!;
    }

    expect([for (var i = 0; i < 12; i++) shown(i)], ['12', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11']);
  });

  testWidgets('12-hour mode: from 11 AM the neighbours are 10 AM and nothing below; it never crosses into noon',
      (tester) async {
    await _open(tester, use24h: false, initial: DateTime(2026, 10, 8, 11, 40), first: _now);
    await _tapIn(tester, find.byKey(BBWhenPicker.dayKey(1)));
    expect(_confirmLabel(tester), 'Set 11:40 AM tomorrow');
    final hour = find.byKey(BBWhenPicker.hourWheelKey);
    final wheel = tester.widget<ListWheelScrollView>(hour);
    final controller = wheel.controller! as FixedExtentScrollController;
    expect(controller.selectedItem, 11);

    // A finger dragging the wheel on, past the last item: it stays at 11 AM.
    await tester.drag(hour, Offset(0, -wheel.itemExtent * 1.2));
    await tester.pumpAndSettle();
    expect(controller.selectedItem, 11);
    expect(_confirmLabel(tester), 'Set 11:40 AM tomorrow');

    // One notch back is 10 AM: the same half of the day.
    await tester.drag(hour, Offset(0, wheel.itemExtent + 18));
    await tester.pumpAndSettle();
    expect(controller.selectedItem, 10);
    expect(_confirmLabel(tester), 'Set 10:40 AM tomorrow');
  });

  testWidgets('12-hour mode: 12 AM and 12 PM are both item 0, told apart by the period wheel', (tester) async {
    await _open(tester, use24h: false, initial: DateTime(2026, 10, 8, 0, 10), first: _now);
    await _tapIn(tester, find.byKey(BBWhenPicker.dayKey(1)));
    final hours = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.hourWheelKey));
    final period = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.periodWheelKey));
    int item(ListWheelScrollView w) => (w.controller! as FixedExtentScrollController).selectedItem;
    expect(_confirmLabel(tester), 'Set 12:10 AM tomorrow');
    expect((item(hours), item(period)), (0, 0), reason: '12 AM: item 0, AM');

    await _turn(tester, BBWhenPicker.periodWheelKey, 1);
    expect(_confirmLabel(tester), 'Set 12:10 PM tomorrow');
    expect((item(hours), item(period)), (0, 1), reason: '12 PM: item 0, PM');

    // And back: opening on noon puts the wheels on item 0 and PM.
    await tester.pumpWidget(const SizedBox());
    await _open(tester, use24h: false, initial: DateTime(2026, 10, 7, 12, 10), first: _now);
    final noonHours = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.hourWheelKey));
    final noonPeriod = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.periodWheelKey));
    expect((item(noonHours), item(noonPeriod)), (0, 1));
    expect(_confirmLabel(tester), 'Set 12:10 PM today');
  });

  testWidgets('12-hour mode: a screen reader\'s increase and a finger agree on the next hour', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, use24h: false, initial: DateTime(2026, 10, 8, 0, 10), first: _now);
    await _tapIn(tester, find.byKey(BBWhenPicker.dayKey(1)));
    final hour = find.byKey(BBWhenPicker.hourWheelKey);
    int item() => (tester.widget<ListWheelScrollView>(hour).controller! as FixedExtentScrollController).selectedItem;
    expect(tester.getSemantics(hour), isSemantics(
      isSlider: true, label: 'Hour', value: '12 AM', increasedValue: '1 AM',
      hasIncreaseAction: true, hasDecreaseAction: false,
    ));

    // The screen reader: 12 AM → 1 AM.
    tester.semantics.performAction(find.semantics.byLabel('Hour'), SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(_confirmLabel(tester), 'Set 1:10 AM tomorrow');
    expect(item(), 1);

    // A finger turning back to item 0 and on to item 1 lands on the same thing.
    await _turn(tester, BBWhenPicker.hourWheelKey, 0);
    expect(_confirmLabel(tester), 'Set 12:10 AM tomorrow');
    await _turn(tester, BBWhenPicker.hourWheelKey, 1);
    expect(_confirmLabel(tester), 'Set 1:10 AM tomorrow');

    // At the end of the wheel (11 AM) there is no further hour to increase to; decrease is 10 AM.
    await _turn(tester, BBWhenPicker.hourWheelKey, 11);
    expect(tester.getSemantics(hour), isSemantics(
      isSlider: true, label: 'Hour', value: '11 AM', decreasedValue: '10 AM',
      hasIncreaseAction: false, hasDecreaseAction: true,
    ));
    tester.semantics.performAction(find.semantics.byLabel('Hour'), SemanticsAction.decrease);
    await tester.pumpAndSettle();
    expect(_confirmLabel(tester), 'Set 10:10 AM tomorrow');
    expect(item(), 10);
    handle.dispose();
  });

  testWidgets('12-hour mode: the hour wheel names the period, so 11 AM and 12 PM are told apart', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, use24h: false);
    final hour = find.byKey(BBWhenPicker.hourWheelKey);
    expect(tester.getSemantics(hour), isSemantics(
      isSlider: true, label: 'Hour', value: '8 AM', increasedValue: '9 AM', decreasedValue: '7 AM',
      hasIncreaseAction: true, hasDecreaseAction: true,
    ));
    await _turn(tester, BBWhenPicker.hourWheelKey, 11); // "11", AM
    expect(tester.getSemantics(hour), isSemantics(
      isSlider: true, label: 'Hour', value: '11 AM', decreasedValue: '10 AM', hasDecreaseAction: true,
    ));
    await _turn(tester, BBWhenPicker.periodWheelKey, 1);
    await _turn(tester, BBWhenPicker.hourWheelKey, 0); // "12", PM
    expect(tester.getSemantics(hour), isSemantics(
      isSlider: true, label: 'Hour', value: '12 PM', increasedValue: '1 PM',
    ));
    handle.dispose();
  });

  testWidgets('the wheel values above and below the centre stay readable: ink at the fade is 4.5:1 on the sheet '
      '(light and dark)', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(const SizedBox());
      await _open(tester, brightness: b, use24h: false);
      final colors = (b == Brightness.dark ? BBTokens.dark : BBTokens.light).colors;
      for (final wheel in [BBWhenPicker.hourWheelKey, BBWhenPicker.minuteWheelKey, BBWhenPicker.periodWheelKey]) {
        final w = tester.widget<ListWheelScrollView>(find.byKey(wheel));
        expect(w.overAndUnderCenterOpacity, BBWhenPicker.neighbourOpacity, reason: '${b.name} $wheel');
        final text = tester.widget<Text>(find.descendant(of: find.byKey(wheel), matching: find.byType(Text)).first);
        expect(text.style!.color, colors.ink, reason: 'neighbours are drawn in ink, faded by the wheel');
      }
      final faded = Color.alphaBlend(colors.ink.withValues(alpha: BBWhenPicker.neighbourOpacity), colors.surface);
      expect(contrast(faded, colors.surface), greaterThanOrEqualTo(4.5), reason: b.name);
    }
  });

  testWidgets('on a phone the sheet slides in and out solid: nothing behind it shows through', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _open(tester);
    // Close, and look half-way down.
    await tester.tap(find.byKey(BBWhenPicker.closeKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(BBWhenPicker.sheetKey), findsOneWidget, reason: 'still on its way down');
    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(of: find.byKey(BBWhenPicker.sheetKey), matching: find.byType(FadeTransition)),
    );
    expect(fades.where((f) => f.opacity.value < 1), isEmpty, reason: 'the sheet itself never fades');
    await tester.pumpAndSettle();
  });

  testWidgets('quick picks set the day and time at once and move the wheels', (tester) async {
    final opened = await _open(tester);
    await _tapIn(tester, find.text('In 30 min'));
    expect(_confirmLabel(tester), 'Set 08:31 today');
    final minutes = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.minuteWheelKey));
    expect((minutes.controller! as FixedExtentScrollController).selectedItem, 31);

    await _tapIn(tester, find.text('17:00'));
    expect(_confirmLabel(tester), 'Set 17:00 today');

    // 08:00 has passed at 08:01, so it means tomorrow.
    await _tapIn(tester, find.text('08:00'));
    expect(_confirmLabel(tester), 'Set 08:00 tomorrow');
    expect(tester.getSemantics(find.byKey(BBWhenPicker.dayKey(1))), isSemantics(isSelected: true));
    await _confirm(tester);
    expect(opened.result, DateTime(2026, 10, 8, 8));
  });

  testWidgets('In 15 min at 23:50 lands on tomorrow', (tester) async {
    await _open(tester, first: DateTime(2026, 10, 7, 23, 50), initial: DateTime(2026, 10, 7, 23, 55));
    await _tapIn(tester, find.text('In 15 min'));
    expect(_confirmLabel(tester), 'Set 00:05 tomorrow');
  });

  testWidgets('a feed that ends today: only Today, and no quick pick past it', (tester) async {
    await _open(tester, first: DateTime(2026, 10, 7, 23, 0), initial: DateTime(2026, 10, 7, 23, 30), last: DateTime(2026, 10, 7));
    expect(find.byKey(BBWhenPicker.dayKey(0)), findsOneWidget);
    expect(find.byKey(BBWhenPicker.dayKey(1)), findsNothing);
    expect(find.text('In 1 hr'), findsNothing, reason: 'lands tomorrow');
    expect(find.text('08:00'), findsNothing);
    expect(find.text('In 15 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a feed that already ended (last before first) still opens on today', (tester) async {
    final opened = await _open(tester, last: DateTime(2026, 10, 1), initial: DateTime(2026, 10, 3, 9));
    expect(find.byKey(BBWhenPicker.dayKey(0)), findsOneWidget);
    expect(find.byKey(BBWhenPicker.dayKey(1)), findsNothing);
    await _confirm(tester);
    expect(opened.result, DateTime(2026, 10, 7, 9), reason: 'the day is clamped to today, the time kept');
  });

  testWidgets('a past time today is allowed but says so, and offers now instead', (tester) async {
    final opened = await _open(tester);
    expect(find.byKey(BBWhenPicker.pastKey), findsNothing);
    await _turn(tester, BBWhenPicker.hourWheelKey, 7);
    expect(find.text("That's in the past"), findsOneWidget);
    expect(_confirmLabel(tester), 'Use now instead');
    await _confirm(tester);
    expect(opened.result, _now);
  });

  testWidgets('Close returns nothing', (tester) async {
    final opened = await _open(tester);
    await tester.tap(find.byKey(BBWhenPicker.closeKey));
    await tester.pumpAndSettle();
    expect(opened.closed, isTrue);
    expect(opened.result, isNull);
  });

  testWidgets('screen readers: wheels are sliders with increase and decrease; chips are selectable buttons; '
      'the time is announced on open (the route already names the title) and on confirm', (tester) async {
    final handle = tester.ensureSemantics();
    final opened = await _open(tester);
    expect(tester.takeAnnouncements(), contains(isAccessibilityAnnouncement('08:35 today')));

    final hour = find.byKey(BBWhenPicker.hourWheelKey);
    expect(tester.getSemantics(hour), isSemantics(
      isSlider: true, label: 'Hour', value: '8 hours', increasedValue: '9 hours', decreasedValue: '7 hours',
      hasIncreaseAction: true, hasDecreaseAction: true,
    ));
    tester.semantics.performAction(find.semantics.byLabel('Hour'), SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(hour), isSemantics(isSlider: true, label: 'Hour', value: '9 hours'));
    expect(_confirmLabel(tester), 'Set 09:35 today');

    final minute = find.byKey(BBWhenPicker.minuteWheelKey);
    expect(tester.getSemantics(minute), isSemantics(isSlider: true, label: 'Minute', value: '35 minutes'));
    tester.semantics.performAction(find.semantics.byLabel('Minute'), SemanticsAction.decrease);
    await tester.pumpAndSettle();
    expect(_confirmLabel(tester), 'Set 09:34 today');

    expect(tester.getSemantics(find.byKey(BBWhenPicker.dayKey(0))),
        isSemantics(isButton: true, isSelected: true, isInMutuallyExclusiveGroup: true, label: 'Today, Wednesday, October 7'));
    expect(tester.getSemantics(find.byKey(BBWhenPicker.dayKey(2))), isSemantics(isButton: true, isSelected: false));

    await _confirm(tester);
    expect(tester.takeAnnouncements(), contains(isAccessibilityAnnouncement('Leave by 09:34 today')));
    expect(opened.result, DateTime(2026, 10, 7, 9, 34));
    handle.dispose();
  });

  testWidgets('2× text at 320×640: rows grow with the text, nothing overflows, the button is reachable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final b in Brightness.values) {
      await tester.pumpWidget(const SizedBox()); // a fresh app each time, with no picker left open
      await _open(tester, textScale: 1, brightness: b);
      final small = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.hourWheelKey)).itemExtent;
      await tester.pumpWidget(const SizedBox());
      await _open(tester, textScale: 2, brightness: b, use24h: false);
      expect(tester.takeException(), isNull, reason: '${b.name} layout');
      final big = tester.widget<ListWheelScrollView>(find.byKey(BBWhenPicker.hourWheelKey)).itemExtent;
      expect(big, greaterThanOrEqualTo(small * 1.9), reason: 'the wheel rows scale with the text');
      await tester.ensureVisible(find.byKey(BBWhenPicker.confirmKey));
      await tester.pumpAndSettle();
      expect(find.byKey(BBWhenPicker.confirmKey).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${b.name} scrolled');
    }
  });

  testWidgets('on a tablet it is a centred card', (tester) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);
    final card = tester.getRect(find.byKey(BBWhenPicker.sheetKey));
    expect(card.width, lessThanOrEqualTo(420));
    expect(card.center.dx, closeTo(512, 1));
    expect(card.center.dy, closeTo(683, 1));
  });

  testWidgets('no Material or Cupertino picker anywhere (spec §4.1)', (tester) async {
    await _open(tester);
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(find.byType(CupertinoPicker), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(BBWhenPicker.sheetKey),
        matching: find.byWidgetPredicate((w) => w is Material || w.runtimeType.toString().startsWith('Cupertino')),
      ),
      findsNothing,
    );
  });

  testWidgets('it builds with no MaterialLocalizations at all', (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: BBTheme.light(),
        child: Localizations(
          locale: const Locale('en'),
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: BBWhenPicker(
              title: 'Arrive by',
              initial: DateTime(2026, 10, 7, 9),
              first: _now,
              last: DateTime(2026, 10, 10),
              use24h: true,
              onDone: (_) {},
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Arrive by'), findsOneWidget);
  });
}

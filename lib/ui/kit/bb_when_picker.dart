import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'bb_button.dart';
import 'bb_card.dart';
import 'bb_icon_button.dart';
import 'bb_icons.dart';
import 'bb_pressable.dart';
import 'bb_time.dart';
import 'tokens.dart';

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime _minuteOf(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute);
int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// BusBoard's own day-and-time picker (visual refresh spec §4), the same on iOS and Android: a
/// bottom sheet on phones, a centred card on tablets, springing up over a dimmed backdrop.
///
/// Days run from [first]'s day to [last]'s day; [first] is "now". Returns the picked moment (to
/// the minute), [first] when the rider picks "Use now instead" for a time in the past, or null
/// when they close it.
Future<DateTime?> showBBWhenPicker(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime first,
  required DateTime last,
  required bool use24h,
}) {
  final wide = MediaQuery.sizeOf(context).shortestSide >= BBWhenPicker.wideBreakpoint;
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: BBScrim.strong,
    transitionDuration: BBMotion.of(context, BBMotion.emphasis),
    pageBuilder: (dialogContext, _, _) => BBWhenPicker(
      title: title,
      initial: initial,
      first: first,
      last: last,
      use24h: use24h,
      wide: wide,
      onDone: (picked) => Navigator.of(dialogContext).pop(picked),
    ),
    transitionBuilder: (_, animation, _, child) {
      if (!wide) {
        // The sheet slides up from below the screen, solid: fading it would show the options through it.
        // The plain curve, not the spring, so an overshoot never lifts it off the bottom edge.
        return SlideTransition(
          position: animation.drive(CurveTween(curve: BBMotion.curve)).drive(
                Tween(begin: const Offset(0, 1), end: Offset.zero),
              ),
          child: child,
        );
      }
      final rise = animation.drive(CurveTween(curve: BBMotion.emphasisCurve));
      return FadeTransition(
        // Opacity stays within 0..1: it follows the plain curve, not the spring.
        opacity: animation.drive(CurveTween(curve: BBMotion.curve)),
        child: ScaleTransition(scale: rise.drive(Tween(begin: 0.94, end: 1.0)), child: child),
      );
    },
  );
}

/// The picker sheet itself; [showBBWhenPicker] presents it. [onDone] gets the result.
class BBWhenPicker extends StatefulWidget {
  const BBWhenPicker({
    super.key,
    required this.title,
    required this.initial,
    required this.first,
    required this.last,
    required this.use24h,
    required this.onDone,
    this.wide = false,
  });

  /// "Leave by" or "Arrive by".
  final String title;
  final DateTime initial;

  /// The earliest moment (now): the first day, and the line before which a time is "in the past".
  final DateTime first;

  /// The last day with service.
  final DateTime last;
  final bool use24h;
  final ValueChanged<DateTime?> onDone;

  /// A centred card (tablets) instead of a bottom sheet.
  final bool wide;

  static const double wideBreakpoint = 600;

  /// How visible the wheel values above and below the centre one are: `ink` at this opacity stays at 4.5:1 or
  /// better on the sheet (Ruling 5), so the fade reads as depth without dropping below WCAG AA.
  static const double neighbourOpacity = 0.65;
  static const sheetKey = ValueKey('bb-when-sheet');
  static const closeKey = ValueKey('bb-when-close');
  static const hourWheelKey = ValueKey('bb-when-hour');
  static const minuteWheelKey = ValueKey('bb-when-minute');
  static const periodWheelKey = ValueKey('bb-when-period');
  static const confirmKey = ValueKey('bb-when-confirm');
  static const pastKey = ValueKey('bb-when-past');
  static Key dayKey(int index) => ValueKey('bb-when-day-$index');

  @override
  State<BBWhenPicker> createState() => _BBWhenPickerState();
}

class _BBWhenPickerState extends State<BBWhenPicker> {
  late final List<DateTime> _days;
  late int _day;
  late int _hour; // 0–23
  late int _minute; // 0–59
  late final FixedExtentScrollController _hourWheel;
  late final FixedExtentScrollController _minuteWheel;
  late final FixedExtentScrollController _periodWheel;

  /// The wheels are being turned by code (a quick pick): no haptic ticks.
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    final start = _dayOf(widget.first);
    final lastDay = _dayOf(widget.last);
    final end = lastDay.isBefore(start) ? start : lastDay;
    _days = [for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) d];
    final initial = _clamp(_minuteOf(widget.initial));
    _day = _daysBetween(start, initial);
    _hour = initial.hour;
    _minute = initial.minute;
    _hourWheel = FixedExtentScrollController(initialItem: _hourItem(_hour));
    _minuteWheel = FixedExtentScrollController(initialItem: _minute);
    _periodWheel = FixedExtentScrollController(initialItem: _hour < 12 ? 0 : 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announce('${widget.title}, ${_spoken(_value)}');
    });
  }

  @override
  void dispose() {
    _hourWheel.dispose();
    _minuteWheel.dispose();
    _periodWheel.dispose();
    super.dispose();
  }

  /// [t] with its day moved into the picker's days, its time of day kept.
  DateTime _clamp(DateTime t) {
    final day = _dayOf(t);
    final d = day.isBefore(_days.first) ? _days.first : (day.isAfter(_days.last) ? _days.last : day);
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  /// The hour wheel's item for [hour]: the hour itself in 24-hour mode; 0–11 for "1"–"12" otherwise.
  int _hourItem(int hour) => widget.use24h ? hour : (hour % 12 == 0 ? 11 : hour % 12 - 1);

  /// What the hour wheel shows for [hour].
  int _shownHour(int hour) => widget.use24h ? hour : (hour % 12 == 0 ? 12 : hour % 12);

  DateTime get _value {
    final d = _days[_day];
    return DateTime(d.year, d.month, d.day, _hour, _minute);
  }

  bool get _past => _value.isBefore(_minuteOf(widget.first));

  String _clock(DateTime t) => BBTime.of(t, use24h: widget.use24h);

  /// "today", "tomorrow", "Thursday", or "Thu, Oct 22" from a week out.
  String _dayWord(DateTime t) {
    final n = _daysBetween(_days.first, t);
    if (n == 0) return 'today';
    if (n == 1) return 'tomorrow';
    if (n < 7) return DateFormat('EEEE').format(t);
    return DateFormat('EEE, MMM d').format(t);
  }

  String _spoken(DateTime t) => '${_clock(t)} ${_dayWord(t)}';

  String _chipLabel(int i) {
    if (i == 0) return 'Today';
    if (i == 1) return 'Tomorrow';
    return DateFormat(i < 7 ? 'EEE' : 'EEE d').format(_days[i]);
  }

  String _chipSpoken(int i) {
    final full = DateFormat('EEEE, MMMM d').format(_days[i]);
    if (i == 0) return 'Today, $full';
    if (i == 1) return 'Tomorrow, $full';
    return full;
  }

  void _announce(String message) =>
      unawaited(SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context)));

  void _tick() {
    if (!_moving) HapticFeedback.selectionClick();
  }

  void _onHour(int item) {
    setState(() => _hour = widget.use24h ? item : ((item + 1) % 12) + (_hour >= 12 ? 12 : 0));
    _tick();
  }

  void _onMinute(int item) {
    setState(() => _minute = item);
    _tick();
  }

  void _onPeriod(int item) {
    setState(() => _hour = _hour % 12 + (item == 1 ? 12 : 0));
    _tick();
  }

  /// Sets the day and time at once and turns the wheels to it.
  Future<void> _set(DateTime t) async {
    final target = _clamp(_minuteOf(t));
    setState(() {
      _day = _daysBetween(_days.first, target);
      _hour = target.hour;
      _minute = target.minute;
    });
    final d = BBMotion.of(context, BBMotion.standard);
    Future<void> turn(FixedExtentScrollController c, int item) async {
      if (!c.hasClients) return;
      if (d == Duration.zero) {
        c.jumpToItem(item);
      } else {
        await c.animateToItem(item, duration: d, curve: BBMotion.curve);
      }
    }

    _moving = true;
    await Future.wait([
      turn(_hourWheel, _hourItem(target.hour)),
      turn(_minuteWheel, target.minute),
      if (!widget.use24h) turn(_periodWheel, target.hour < 12 ? 0 : 1),
    ]);
    _moving = false;
    // The wheels report every item they pass; end exactly on the target.
    if (mounted) {
      setState(() {
        _hour = target.hour;
        _minute = target.minute;
      });
    }
  }

  /// Quick picks: label and moment, minus any after the last day.
  List<(String, String, DateTime)> get _quickPicks {
    final now = _minuteOf(widget.first);
    DateTime next(int hour) {
      final today = DateTime(now.year, now.month, now.day, hour);
      return today.isAfter(now) ? today : DateTime(now.year, now.month, now.day + 1, hour);
    }

    final eight = next(8), five = next(17);
    return [
      ('In 15 min', 'In 15 minutes', now.add(const Duration(minutes: 15))),
      ('In 30 min', 'In 30 minutes', now.add(const Duration(minutes: 30))),
      ('In 1 hr', 'In 1 hour', now.add(const Duration(hours: 1))),
      (_clock(eight), '${_clock(eight)} ${_dayWord(eight)}', eight),
      (_clock(five), '${_clock(five)} ${_dayWord(five)}', five),
    ].where((p) => !_dayOf(p.$3).isAfter(_days.last)).toList();
  }

  void _confirm() {
    final picked = _past ? widget.first : _value;
    _announce('${widget.title} ${_spoken(picked)}');
    widget.onDone(picked);
  }

  Widget _wheel({
    required Key key,
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
    required String semanticLabel,
    required String value,
    required String? increased,
    required String? decreased,
    required VoidCallback? onIncrease,
    required VoidCallback? onDecrease,
    required double itemExtent,
    required int visible,
  }) {
    final bb = context.bb;
    return Semantics(
      container: true,
      slider: true,
      label: semanticLabel,
      value: value,
      increasedValue: increased,
      decreasedValue: decreased,
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      child: ExcludeSemantics(
        child: SizedBox(
          height: itemExtent * visible,
          child: ListWheelScrollView.useDelegate(
            key: key,
            controller: controller,
            itemExtent: itemExtent,
            physics: const FixedExtentScrollPhysics(),
            diameterRatio: 1.6,
            overAndUnderCenterOpacity: BBWhenPicker.neighbourOpacity,
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: count,
              builder: (context, i) => Center(
                child: Text(
                  label(i),
                  maxLines: 1,
                  style: bb.text.title.copyWith(
                    color: bb.colors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wheels(double itemExtent, int visible) {
    final bb = context.bb;
    final d = _days[_day];
    DateTime at(int hour, int minute) => DateTime(d.year, d.month, d.day, hour, minute);
    // 24-hour: "8 hours". 12-hour names the period too ("11 AM", "12 PM"), since the wheel shows 1–12.
    String hours(int h) => widget.use24h
        ? '$h ${h == 1 ? 'hour' : 'hours'}'
        : '${_shownHour(h)} ${h < 12 ? 'AM' : 'PM'}';
    String minutes(int m) => '$m ${m == 1 ? 'minute' : 'minutes'}';
    final pm = _hour >= 12;
    return Stack(
      alignment: Alignment.center,
      children: [
        // The selection band.
        IgnorePointer(
          child: Container(
            height: itemExtent,
            decoration: BoxDecoration(color: bb.colors.brandSoft, borderRadius: BorderRadius.circular(BBRadius.button)),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _wheel(
                key: BBWhenPicker.hourWheelKey,
                controller: _hourWheel,
                count: widget.use24h ? 24 : 12,
                label: (i) => widget.use24h ? i.toString().padLeft(2, '0') : '${i + 1}',
                onChanged: _onHour,
                semanticLabel: 'Hour',
                value: hours(_hour),
                increased: _hour < 23 ? hours(_hour + 1) : null,
                decreased: _hour > 0 ? hours(_hour - 1) : null,
                onIncrease: _hour < 23 ? () => _set(at(_hour + 1, _minute)) : null,
                onDecrease: _hour > 0 ? () => _set(at(_hour - 1, _minute)) : null,
                itemExtent: itemExtent,
                visible: visible,
              ),
            ),
            ExcludeSemantics(child: Text(':', style: bb.text.title)),
            Expanded(
              child: _wheel(
                key: BBWhenPicker.minuteWheelKey,
                controller: _minuteWheel,
                count: 60,
                label: (i) => i.toString().padLeft(2, '0'),
                onChanged: _onMinute,
                semanticLabel: 'Minute',
                value: minutes(_minute),
                increased: _minute < 59 ? minutes(_minute + 1) : null,
                decreased: _minute > 0 ? minutes(_minute - 1) : null,
                onIncrease: _minute < 59 ? () => _set(at(_hour, _minute + 1)) : null,
                onDecrease: _minute > 0 ? () => _set(at(_hour, _minute - 1)) : null,
                itemExtent: itemExtent,
                visible: visible,
              ),
            ),
            if (!widget.use24h)
              Expanded(
                child: _wheel(
                  key: BBWhenPicker.periodWheelKey,
                  controller: _periodWheel,
                  count: 2,
                  label: (i) => i == 0 ? 'AM' : 'PM',
                  onChanged: _onPeriod,
                  semanticLabel: 'AM or PM',
                  value: pm ? 'PM' : 'AM',
                  increased: pm ? null : 'PM',
                  decreased: pm ? 'AM' : null,
                  onIncrease: pm ? null : () => _set(at(_hour + 12, _minute)),
                  onDecrease: pm ? () => _set(at(_hour - 12, _minute)) : null,
                  itemExtent: itemExtent,
                  visible: visible,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _chip({
    Key? key,
    required String label,
    required String semanticLabel,
    required bool selected,
    required VoidCallback onTap,
    bool selectable = true,
  }) {
    final bb = context.bb;
    final pill = BBPressable(
      key: key,
      haptic: !selected,
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: AnimatedContainer(
        duration: BBMotion.of(context, BBMotion.standard),
        curve: BBMotion.curve,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: BBSpace.l, vertical: BBSpace.s),
        // Selected: the brand fill with onBrand text (spec §4.1).
        decoration: selected
            ? BoxDecoration(color: bb.colors.brand, borderRadius: BorderRadius.circular(22))
            : bb.field(radius: 22),
        // As wide as its label (no `alignment`, which would fill a Wrap's width), centred in the 44 pt height.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              style: bb.text.label.copyWith(color: selected ? bb.colors.onBrand : bb.colors.ink),
            ),
          ],
        ),
      ),
    );
    if (!selectable) return pill;
    return Semantics(selected: selected, inMutuallyExclusiveGroup: true, child: pill);
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(1);
    // Wheel rows grow with the text (spec §4.2); at large sizes, three rows show instead of five.
    final itemExtent = media.textScaler.scale(bb.text.title.fontSize!) * 1.6;
    final visible = textScale > 1.3 ? 3 : 5;
    final value = _value;
    final past = _past;
    const radius = Radius.circular(BBRadius.sheet);

    final sheet = Container(
      key: BBWhenPicker.sheetKey,
      decoration: bb.floating(
        borderRadius: widget.wide ? BorderRadius.all(radius) : BorderRadius.vertical(top: radius),
      ),
      child: BBSurfaceScope(
        child: SafeArea(
          top: false,
          bottom: !widget.wide,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.s, BBSpace.l, BBSpace.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(header: true, child: Text(widget.title, style: bb.text.title)),
                    ),
                    BBIconButton(
                      key: BBWhenPicker.closeKey,
                      icon: BBIcons.close,
                      semanticLabel: 'Close',
                      onPressed: () => widget.onDone(null),
                    ),
                  ],
                ),
                const SizedBox(height: BBSpace.s),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _days.length; i++) ...[
                        if (i > 0) const SizedBox(width: BBSpace.s),
                        _chip(
                          key: BBWhenPicker.dayKey(i),
                          label: _chipLabel(i),
                          semanticLabel: _chipSpoken(i),
                          selected: i == _day,
                          onTap: () => setState(() => _day = i),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: BBSpace.m),
                _wheels(itemExtent, visible),
                if (past)
                  Padding(
                    padding: const EdgeInsets.only(top: BBSpace.s),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        "That's in the past",
                        key: BBWhenPicker.pastKey,
                        textAlign: TextAlign.center,
                        style: bb.text.caption,
                      ),
                    ),
                  ),
                const SizedBox(height: BBSpace.m),
                Wrap(
                  spacing: BBSpace.s,
                  runSpacing: BBSpace.s,
                  children: [
                    for (final (label, spoken, t) in _quickPicks)
                      _chip(label: label, semanticLabel: spoken, selected: false, selectable: false, onTap: () => _set(t)),
                  ],
                ),
                const SizedBox(height: BBSpace.l),
                BBButton(
                  key: BBWhenPicker.confirmKey,
                  label: past ? 'Use now instead' : 'Set ${_clock(value)} ${_dayWord(value)}',
                  expand: true,
                  wrap: true,
                  onPressed: _confirm,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final maxHeight = math.max(0.0, media.size.height - media.padding.top - BBSpace.xxl);
    return DefaultTextStyle(
      style: bb.text.body,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: widget.title,
        child: widget.wide
            ? Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
                  child: sheet,
                ),
              )
            : Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight), child: sheet),
              ),
      ),
    );
  }
}

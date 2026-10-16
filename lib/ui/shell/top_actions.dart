import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../routing/push_once.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../kit/kit.dart';

/// The three buttons at the top right of both tabs, in this order: Plan, Alerts (the Alerts tab's megaphone, counting
/// the active service alerts) and Settings. Each opens its page over the tabs; back returns to the tab.
///
/// In the Board's headers they are icon buttons like the gear they replace; on the map ([floating]) each is a round
/// floating button, as the map's my-location control is.
class TopActions extends ConsumerWidget {
  const TopActions({super.key, this.floating = false});

  /// Round floating buttons over the map, in place of header icon buttons.
  final bool floating;

  static const planKey = ValueKey('top-plan');
  static const alertsKey = ValueKey('top-alerts');
  static const settingsKey = ValueKey('top-settings');

  /// The alerts button's screen-reader label: "Service alerts, 2 active".
  static String alertsLabel(int active) => active > 0 ? 'Service alerts, $active active' : 'Service alerts';

  /// Opens the trip planner with [push] (a [PushOnce]'s, so a quick double tap opens one). A trip whose steps the
  /// rider left open (Show on map, Follow bus, a notification) comes back over the planner, as on 1.4.1's Plan tab.
  /// The Plan button does this, and so does the stop picker's Plan a trip card.
  static void openPlanner(BuildContext context, WidgetRef ref, PushOnceCallback push) => push(
        '/plan',
        then: () {
          final open = ref.read(openJourneyProvider.notifier).stillUnderWay(ref.read(plannerClockProvider)());
          if (open != null) unawaited(GoRouter.of(context).push('/plan/journey', extra: open));
        },
      );

  /// The width of the three header buttons (44 pt each).
  static const double headerWidth = 3 * 44;

  /// [text] in [style] reads in full within [width] at the current text size: no word broken or cut, in [maxLines].
  /// Where it does not, a header puts the buttons on a row of their own above it (large text on a small phone).
  static bool fits(BuildContext context, String text, TextStyle style, double width, {int maxLines = 1}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: maxLines,
    )..layout(maxWidth: width);
    final fits = !painter.didExceedMaxLines && painter.minIntrinsicWidth <= width;
    painter.dispose();
    return fits;
  }

  /// The width [text] takes on one line in [style] at the current text size.
  static double textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(serviceUpdatesProvider).value?.activeAlertsAt(DateTime.now()).length ?? 0;
    final gap = floating ? BBSpace.s : 0.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TopButton(
          buttonKey: planKey,
          icon: BBIcons.plan,
          label: 'Plan a trip',
          floating: floating,
          onTap: (push) => openPlanner(context, ref, push),
        ),
        SizedBox(width: gap),
        _TopButton(
          buttonKey: alertsKey,
          icon: BBIcons.alerts,
          label: alertsLabel(active),
          onTap: (push) => push('/alerts'),
          floating: floating,
          badgeCount: active,
        ),
        SizedBox(width: gap),
        _TopButton(
          buttonKey: settingsKey,
          icon: BBIcons.settings,
          label: 'Settings',
          onTap: (push) => push('/settings'),
          floating: floating,
        ),
      ],
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.floating,
    required this.onTap,
    this.badgeCount = 0,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final bool floating;
  final int badgeCount;

  /// Opens the button's page with a [PushOnce]'s push.
  final void Function(PushOnceCallback push) onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    // A 44 pt target, like BBIconButton; the count sits on the icon's shoulder and is said in the label.
    Widget face = SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: Icon(icon, size: 22, color: bb.colors.ink)),
          if (badgeCount > 0)
            Positioned(
              top: 4,
              right: 2,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: BBNavBar.maxTextScale,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: bb.colors.dangerInk, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '$badgeCount',
                    textAlign: TextAlign.center,
                    style: bb.text.caption.copyWith(
                      color: bb.colors.surface,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (floating) face = DecoratedBox(decoration: bb.floating(radius: 22), child: face);
    // Once for a quick double tap: two taps before the page shows would open two.
    return PushOnce(
      builder: (context, push) =>
          BBPressable(key: buttonKey, semanticLabel: label, onTap: () => onTap(push), child: face),
    );
  }
}

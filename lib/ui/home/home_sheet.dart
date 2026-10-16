import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/realtime/service_alert_models.dart';
import '../../data/trip_planner/saved_place_store.dart';
import '../../domain/location/locate_me.dart';
import '../../state/alerts_for_you_provider.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/providers.dart';
import '../../state/saved_place_providers.dart';
import '../../state/trip_planner_providers.dart';
import '../alerts/service_alert_card.dart';
import '../arrival_alerts/alert_strip.dart';
import '../kit/kit.dart';
import '../map/stop_card.dart';
import '../stop_picker/near_me_list.dart';
import '../trip_planner/saved_trips_section.dart';
import 'home_stop_line.dart';
import 'home_tip.dart';

/// The home sheet (spec 2026-10-12 §3.1, 2026-10-14 §3). On a phone its header is the slim bar that rests over the
/// map: Where to? and your stop's line ([bar]); pulled up, [barBody] shows saved places, alerts for you, your stop's
/// next buses with Open board, saved trips and nearby stops. The tablet panel keeps the full [header] and [body].
abstract final class HomeSheetContent {
  static const whereToKey = ValueKey('where-to');
  static const openBoardKey = ValueKey('home-open-board');

  /// [onChooseStop] pulls the sheet up to the nearby stops (home_screen.dart passes its sheet's full detent). With no
  /// nearby stops to show (no location, or none near) "Choose your stop" opens a stop search instead (spec §4.4).
  static Widget bar({VoidCallback? onChooseStop}) => _Bar(onChooseStop: onChooseStop);

  /// Under the bar: everything the bar leaves out, then saved trips and nearby stops.
  static Widget barBody() => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_Header(belowBar: true), _Body()],
      );

  /// The tablet panel's header, as before the bar (spec 2026-10-14 §3.7).
  static Widget header({VoidCallback? onChooseStop}) => _Header(onChooseStop: onChooseStop);
  static Widget body() => const _Body();
}

/// The phone's bar (spec 2026-10-14 §3.1): Where to? and the stop line, each at least 48 pt tall, under the one-time
/// tip while it shows. An armed arrival alert's strip joins them, so it stays in sight and can be cancelled with the
/// stop's sheet closed (F4). Its height is its content's, so it grows with the text size.
class _Bar extends ConsumerWidget {
  const _Bar({this.onChooseStop});

  final VoidCallback? onChooseStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAlert = ref.watch(arrivalAlertProvider.select((a) => a.value != null));
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeTip(),
          const _WhereTo(),
          const SizedBox(height: BBSpace.s),
          HomeStopLine(onChooseStop: onChooseStop),
          if (hasAlert) ...[const SizedBox(height: BBSpace.s), const AlertStrip()],
        ],
      ),
    );
  }
}

/// "Where to?": the search field, at least 48 pt tall.
class _WhereTo extends StatefulWidget {
  const _WhereTo();

  @override
  State<_WhereTo> createState() => _WhereToState();
}

class _WhereToState extends State<_WhereTo> {
  /// The search this opened is still open: a second tap (a quick double tap, both before the next frame builds the
  /// search page) must not push another.
  bool _open = false;

  /// The search covered this page, so its route is no longer current.
  bool _covered = false;

  void _openSearch() {
    if (_open) return;
    _open = true;
    unawaited(context.push<void>('/search').whenComplete(() => _open = false));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Back on top however the search went (popped, or replaced by a link): Where to? works again.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (!current) {
      _covered = true;
    } else if (_covered) {
      _covered = false;
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return BBPressable(
      key: HomeSheetContent.whereToKey,
      semanticLabel: 'Where to? Search for a place or a stop',
      onTap: _openSearch,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: DecoratedBox(
          decoration: bb.field(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.s),
            child: Row(
              children: [
                Icon(BBIcons.search, size: 20, color: bb.colors.muted),
                const SizedBox(width: BBSpace.s),
                Expanded(
                  child: Text('Where to?', style: bb.text.title.copyWith(color: bb.colors.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The icon for a saved place's kind.
IconData savedPlaceIconData(SavedPlaceIcon i) => switch (i) {
  SavedPlaceIcon.home => BBIcons.home,
  SavedPlaceIcon.work => BBIcons.work,
  SavedPlaceIcon.school => BBIcons.school,
  SavedPlaceIcon.star => BBIcons.star,
};

class _Header extends ConsumerWidget {
  const _Header({this.onChooseStop, this.belowBar = false});

  final VoidCallback? onChooseStop;

  /// Under the phone's bar, which already has the tip, Where to?, "Choose your stop" and an armed alert's strip.
  final bool belowBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final places = ref.watch(savedPlacesProvider).value ?? const <SavedPlace>[];
    final alerts = ref.watch(alertsForYouProvider);
    final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
    final stop = stopId == null ? null : ref.watch(stopInfoProvider(stopId));
    final hasAlert = ref.watch(arrivalAlertProvider.select((a) => a.value != null));
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!belowBar) ...[const HomeTip(), const _WhereTo()],
          const SizedBox(height: BBSpace.s),
          Wrap(
            spacing: BBSpace.s,
            runSpacing: BBSpace.s,
            children: [
              for (final p in places)
                Semantics(
                  // A screen reader reaches Remove through the long-press action.
                  onLongPress: () => _editPlace(context, ref, p),
                  onLongPressHint: 'Remove',
                  child: GestureDetector(
                    onLongPress: () => _editPlace(context, ref, p),
                    child: BBChip(
                      label: p.name,
                      icon: savedPlaceIconData(p.icon),
                      semanticLabel: 'Go to ${p.name}',
                      onTap: () {
                        // A new trip to the place, from the phone's position, leaving now (Ruling 14).
                        final q = ref.read(planQueryProvider.notifier)..startFresh(p.place);
                        ref.read(homeSheetProvider.notifier).open(const OptionsSheet());
                        unawaited(locateMe().then((here) {
                          if (here != null) q.fillStart(here);
                        }));
                      },
                    ),
                  ),
                ),
              BBChip(
                label: places.isEmpty ? 'Save a place' : 'Add',
                icon: BBIcons.add,
                semanticLabel: 'Save a place',
                onTap: () => context.push('/search?save=1'),
              ),
            ],
          ),
          for (final a in alerts.take(2)) _AlertRow(alert: a),
          // An armed arrival alert stays in sight, and can be cancelled, once its stop's sheet is closed.
          if (hasAlert && !belowBar) ...[const SizedBox(height: BBSpace.s), const AlertStrip()],
          const SizedBox(height: BBSpace.m),
          if (stop == null && belowBar)
            const SizedBox.shrink()
          else if (stop == null)
            BBButton(
              label: 'Choose your stop',
              icon: BBIcons.nearMe,
              kind: BBButtonKind.quiet,
              expand: true,
              onPressed: () {
                // Nearby stops to pick from: pull up to them. None (location off or refused, or nothing near): a
                // search for the stop number on the pole (spec §4.4).
                final nearby = ref.read(nearestStopsProvider);
                final none = nearby.hasError || (nearby.hasValue && nearby.value!.isEmpty);
                if (none) {
                  context.push('/search?pickStop=1');
                } else {
                  onChooseStop?.call();
                }
              },
            )
          else ...[
            BBPressable(
              semanticLabel: 'Your stop, ${stop.stopName}. Open its buses',
              onTap: () => ref.read(homeSheetProvider.notifier).open(StopSheet(stop.stopId)),
              child: Row(
                children: [
                  Icon(BBIcons.star, size: 18, color: bb.brandEdge),
                  const SizedBox(width: BBSpace.s),
                  Expanded(
                    child: Text(stop.stopName, style: bb.text.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text('#${stop.stopId}', style: bb.text.caption),
                ],
              ),
            ),
            // For riders used to the Board tab: their stop's whole Board in one tap. The same filled button as in
            // the stop's own sheet, so it reads as the way in, not a link.
            const SizedBox(height: BBSpace.s),
            BBButton(
              key: HomeSheetContent.openBoardKey,
              label: 'Open board',
              semanticLabel: 'Open board, ${stop.stopName}',
              icon: BBIcons.board,
              expand: true,
              wrap: true,
              onPressed: () => ref.read(homeSheetProvider.notifier).openBoard(stop.stopId),
            ),
            ArrivalsPreview(stopId: stop.stopId, max: 3),
          ],
        ],
      ),
    );
  }
}

/// One alert for you, on one line (spec §3.1). The whole row opens Alerts.
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final ServiceAlert alert;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final title = alert.header.isNotEmpty ? alert.header : alert.effect.label;
    return Padding(
      padding: const EdgeInsets.only(top: BBSpace.xs),
      child: BBPressable(
        semanticLabel: 'Alert: $title. Open alerts',
        onTap: () => context.push('/alerts'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              BBIconTile(icon: ServiceAlertCard.iconOf(alert), tone: ServiceAlertCard.toneOf(alert), size: 28),
              const SizedBox(width: BBSpace.s),
              Expanded(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.label),
              ),
              Icon(BBIcons.chevronRight, size: 18, color: bb.colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: BBSpace.m),
        SavedTripsSection(),
        NearMeList(),
      ],
    ),
  );
}

/// Long-press on a saved place: remove it. (Rename and the icon choice come with the save flow, spec §3.5.)
Future<void> _editPlace(BuildContext context, WidgetRef ref, SavedPlace p) async {
  final remove = await BBDialog.show<bool>(
    context,
    title: p.name,
    actions: const [
      BBDialogAction(label: 'Cancel', value: false),
      BBDialogAction(label: 'Remove', value: true, primary: true),
    ],
  );
  if (remove == true) await ref.read(savedPlacesProvider.notifier).remove(p.id);
}

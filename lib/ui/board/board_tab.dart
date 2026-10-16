import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/location/nearest_stop_service.dart';
import '../../state/board_providers.dart';
import '../../state/home_tab_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../home/home_sheet.dart' show WhereToField, savedPlaceIconData;
import '../home/map_buttons.dart';
import '../home/stop_sheet.dart';
import '../kit/kit.dart';
import '../stop_picker/near_me_list.dart';

/// The Board tab (spec 2026-10-15 §3): "when's my bus at my stop?" without the map. Its title with Alerts and
/// Settings, Where to?, a row of stop chips, then the chosen stop's board: the stop sheet's own header, alerts and
/// departures, and Plan a trip from here. Pull to refresh. On a tablet it is a centred column [maxWidth] wide.
class BoardTab extends ConsumerStatefulWidget {
  const BoardTab({super.key});

  static const whereToKey = ValueKey('board-where-to');
  static const nearMeKey = ValueKey('board-chip-near-me');
  static const findStopKey = ValueKey('board-chip-find-stop');
  static const chipsKey = ValueKey('board-chips');
  static const maxWidth = 640.0;

  /// The chip for [chip]'s stop.
  static ValueKey<String> chipKey(BoardChip chip) => ValueKey('board-chip-${chip.kind.name}-${chip.stopId}');

  @override
  ConsumerState<BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends ConsumerState<BoardTab> {
  /// Near me is waiting for a fix.
  bool _locating = false;

  /// Near me: the nearest stop by GPS. None (location off or refused, or no stop near): why, and a search instead.
  Future<void> _nearMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    // A fresh fix every time: the rider may have walked since. Listened to while awaited, so it is not disposed.
    ref.invalidate(nearestStopsProvider);
    final keep = ref.listenManual(nearestStopsProvider, (_, _) {});
    List<NearbyStop> stops = const [];
    try {
      stops = await ref.read(nearestStopsProvider.future);
    } catch (_) {
      // No location: as none near.
    } finally {
      keep.close();
      if (mounted) setState(() => _locating = false);
    }
    if (!mounted) return;
    if (stops.isNotEmpty) {
      ref.read(boardStopProvider.notifier).select(stops.first.stop.stopId, nearMe: true);
      return;
    }
    final search = await BBDialog.show<bool>(
      context,
      title: "Can't find a stop near you",
      message: 'Location may be off for BusBoard, or no stop is within 800 m. '
          'You can search for the number on the stop pole instead.',
      actions: const [
        BBDialogAction(label: 'Cancel', value: false),
        BBDialogAction(label: 'Search instead', value: true, primary: true),
      ],
    );
    if (search == true && mounted) unawaited(context.push('/search?pickStop=1'));
  }

  Future<void> _refresh(String? stopId) async {
    if (stopId == null) return;
    ref.invalidate(stopArrivalsProvider(stopId));
    try {
      await ref.read(stopArrivalsProvider(stopId).future);
    } catch (_) {
      // The board shows the error itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(boardReadyProvider);
    final shown = ref.watch(boardShownStopProvider);
    final stopId = shown?.stopId;
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BoardTab.maxWidth),
          child: BBScrollPage(
            title: 'Board',
            large: true,
            actions: const [AlertsButton(), SettingsButton()],
            body: (context, inset) => BBRefresh(
              semanticLabel: 'Departures',
              topInset: inset,
              onRefresh: () => _refresh(stopId),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: inset)),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: BBSpace.l),
                      child: WhereToField(key: BoardTab.whereToKey),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _StopChips(shown: shown, locating: _locating, onNearMe: _nearMe),
                  ),
                  if (!ready)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(BBSpace.l),
                        child: BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 4, label: 'Loading your stop'),
                      ),
                    )
                  else if (stopId == null)
                    const SliverToBoxAdapter(child: _ChooseYourStop())
                  else ...[
                    SliverToBoxAdapter(
                      key: ValueKey('board-stop-$stopId'),
                      child: Padding(
                        // The icon buttons bring their own hit area on the right.
                        padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.s, BBSpace.s, BBSpace.s),
                        child: StopSheetContent.info(stopId),
                      ),
                    ),
                    SliverToBoxAdapter(child: StopSheetContent.body(stopId)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: BBSpace.l),
                        child: StopSheetContent.planFrom(stopId),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: BBSpace.xxl)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One scrollable row: your stop, saved stops, recent stops, Near me and ＋ (spec §3). The chip of the stop showing
/// is selected (brand fill); each is a button with a selected state.
class _StopChips extends ConsumerWidget {
  const _StopChips({required this.shown, required this.locating, required this.onNearMe});

  final BoardStop? shown;
  final bool locating;
  final VoidCallback onNearMe;

  /// A chip in the row: as wide as its label up to a limit, past which the label ellipsizes.
  static Widget _bounded(Widget chip) =>
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: chip);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = ref.watch(boardChipsProvider);
    final shown = this.shown;
    final selectedIndex =
        shown == null || shown.nearMe ? -1 : chips.indexWhere((c) => c.stopId == shown.stopId);
    String nameOf(String stopId) => ref.watch(stopInfoProvider(stopId))?.stopName ?? 'Stop $stopId';
    final nearMe = shown?.nearMe ?? false;
    return SingleChildScrollView(
      key: BoardTab.chipsKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.m, BBSpace.l, BBSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, chip) in chips.indexed) ...[
            _bounded(BBChip(
              key: BoardTab.chipKey(chip),
              toggle: true,
              selected: i == selectedIndex,
              label: switch (chip.kind) {
                BoardChipKind.saved => chip.place!.name,
                _ => nameOf(chip.stopId),
              },
              icon: switch (chip.kind) {
                BoardChipKind.yours => BBIcons.star,
                BoardChipKind.saved => savedPlaceIconData(chip.place!.icon),
                BoardChipKind.recent => BBIcons.history,
              },
              semanticLabel: switch (chip.kind) {
                BoardChipKind.yours => 'Your stop, ${nameOf(chip.stopId)}',
                BoardChipKind.saved => '${chip.place!.name}, ${nameOf(chip.stopId)}',
                BoardChipKind.recent => 'Recent stop, ${nameOf(chip.stopId)}',
              },
              onTap: () => ref.read(boardStopProvider.notifier).select(chip.stopId),
            )),
            const SizedBox(width: BBSpace.s),
          ],
          _bounded(BBChip(
            key: BoardTab.nearMeKey,
            toggle: true,
            selected: nearMe,
            label: locating ? 'Finding you…' : 'Near me',
            icon: BBIcons.nearMe,
            semanticLabel: nearMe ? 'Near me, ${nameOf(shown!.stopId)}' : 'Near me',
            onTap: onNearMe,
          )),
          const SizedBox(width: BBSpace.s),
          BBChip(
            key: BoardTab.findStopKey,
            label: 'Stop',
            icon: BBIcons.add,
            semanticLabel: 'Choose your stop',
            onTap: () => context.push('/search?pickStop=1'),
          ),
        ],
      ),
    );
  }
}

/// No stop chosen and none saved (spec §3): "Choose your stop" with the nearby stops, as the map's sheet has them; with
/// no location, or no stop near, a search for the number on the pole instead.
class _ChooseYourStop extends ConsumerWidget {
  const _ChooseYourStop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final nearby = ref.watch(nearestStopsProvider);
    final none = nearby.hasError || (nearby.hasValue && nearby.value!.isEmpty);
    if (none) {
      return Padding(
        padding: const EdgeInsets.all(BBSpace.l),
        child: BBEmptyState(
          icon: BBIcons.stop,
          title: 'Choose your stop',
          message: 'Search for the number on the stop pole.',
          action: BBButton(
            label: 'Search for a stop',
            icon: BBIcons.search,
            onPressed: () => context.push('/search?pickStop=1'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.l, BBSpace.l, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Choose your stop', style: bb.text.title)),
          const SizedBox(height: BBSpace.s),
          NearMeList(
            onPick: (stopId) {
              // Chosen here, it is your stop from now on, and the Board shows it.
              unawaited(ref.read(settingsProvider.notifier).setSelectedStop(stopId));
              ref.read(boardStopProvider.notifier).select(stopId);
            },
          ),
        ],
      ),
    );
  }
}

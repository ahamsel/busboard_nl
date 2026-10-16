import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routing/push_once.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';
import '../shell/top_actions.dart';
import 'near_me_list.dart';
import 'stop_id_entry.dart';

class StopPickerScreen extends ConsumerWidget {
  const StopPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final gtfsAsync = ref.watch(gtfsRepositoryProvider);
    final bb = context.bb;

    return BBScaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: LayoutBuilder(builder: (context, box) {
                const title = 'Choose a stop';
                const subtitle = "Metrobus · St. John's";
                // The title beside Plan, Alerts and Settings (BBTopBar's xs padding and m gap), unless large text on
                // a small phone would break its words: then the buttons take a row of their own above it.
                final room = box.maxWidth - 2 * BBSpace.xs - BBSpace.m - TopActions.headerWidth;
                if (TopActions.fits(context, title, bb.text.display, room, maxLines: 2)) {
                  return const BBTopBar(title: title, subtitle: subtitle, large: true, actions: [TopActions()]);
                }
                return const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(BBSpace.xs, BBSpace.s, BBSpace.xs, 0),
                      child: Align(alignment: Alignment.centerRight, child: TopActions()),
                    ),
                    BBTopBar(title: title, subtitle: subtitle, large: true),
                  ],
                );
              }),
            ),
            // A reload that fails (Refresh schedule, offline) keeps the schedule loaded once: Settings says so.
            ...gtfsAsync.when(
              skipError: true,
              data: (_) => [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: BBSpace.screen),
                  sliver: SliverList.list(children: [
                    if (settings.selectedStopId != null) ...[
                      _LastStopCard(stopId: settings.selectedStopId!),
                      const SizedBox(height: BBSpace.xl),
                    ],
                    const StopIdEntry(),
                    const SizedBox(height: BBSpace.xl),
                    Row(children: [
                      const Expanded(child: BBDivider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: BBSpace.m),
                        child: Text('or', style: bb.text.caption),
                      ),
                      const Expanded(child: BBDivider()),
                    ]),
                    const SizedBox(height: BBSpace.xl),
                    const BBCard(padding: EdgeInsets.all(BBSpace.l), child: NearMeList()),
                  ]),
                ),
              ],
              loading: () => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const BBLoading(label: 'Loading schedule data...'),
                      const SizedBox(height: BBSpace.xs),
                      Text('Downloading GTFS feed from Metrobus', style: bb.text.caption),
                    ]),
                  ),
                ),
              ],
              error: (err, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: BBEmptyState(
                      icon: BBIcons.error,
                      tone: BBEmptyTone.error,
                      title: 'Failed to load schedule',
                      message: err.toString(),
                      action: BBButton(
                        label: 'Retry',
                        icon: BBIcons.refresh,
                        onPressed: () => ref.invalidate(gtfsRepositoryProvider),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(child: SizedBox(height: BBNavBar.reservedHeight(context) + BBSpace.l + MediaQuery.viewInsetsOf(context).bottom)),
          ],
        ),
      ),
    );
  }
}

class _LastStopCard extends ConsumerWidget {
  const _LastStopCard({required this.stopId});

  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final name = ref.watch(stopInfoProvider(stopId))?.stopName ?? 'Stop $stopId';
    // Once for a quick double tap: two taps before the Board shows would push two.
    return PushOnce(builder: (context, push) => BBCard(
      onTap: () => push('/board/$stopId'),
      semanticLabel: 'Last stop, $name, stop $stopId',
      child: Row(children: [
        const BBIconTile(icon: BBIcons.history, tone: BBPillTone.live),
        const SizedBox(width: BBSpace.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Last stop', style: bb.text.caption),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.headline),
          ]),
        ),
        Text('#$stopId', style: bb.text.label.copyWith(color: bb.colors.brandInk, fontSize: 15)),
        Icon(BBIcons.chevronRight, color: bb.colors.muted),
      ]),
    ));
  }
}

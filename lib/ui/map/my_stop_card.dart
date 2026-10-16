import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';
import 'stop_card.dart';

/// The sheet when nothing is selected (spec §3.3): your stop's next 1–2
/// arrivals at peek, the full list when dragged up, or an invitation to choose
/// a stop.
abstract final class MyStopCard {
  static Widget header() => const _MyStopHeader();
  static Widget body() => const _MyStopBody();
}

class _MyStopHeader extends ConsumerWidget {
  const _MyStopHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
    final stop = stopId == null ? null : ref.watch(stopInfoProvider(stopId));
    if (stop == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose a stop to see its next buses', style: bb.text.body),
            const SizedBox(height: BBSpace.m),
            BBButton(label: 'Choose a stop', icon: BBIcons.search, expand: true, onPressed: () => context.go('/')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(BBIcons.star, size: 18, color: bb.colors.brand),
              const SizedBox(width: BBSpace.s),
              Expanded(child: Text(stop.stopName, style: bb.text.headline, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: BBSpace.s),
          ArrivalsPreview(stopId: stop.stopId, max: 2),
        ],
      ),
    );
  }
}

class _MyStopBody extends ConsumerWidget {
  const _MyStopBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
    if (stopId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BBSectionHeader(title: 'Later'),
          _LaterArrivals(stopId: stopId),
          const SizedBox(height: BBSpace.m),
          BBButton(
            label: 'Open board',
            icon: BBIcons.board,
            kind: BBButtonKind.quiet,
            expand: true,
            onPressed: () => context.go('/board/$stopId'),
          ),
        ],
      ),
    );
  }
}

/// Arrivals after the first two (those are in the header at peek).
class _LaterArrivals extends ConsumerWidget {
  const _LaterArrivals({required this.stopId});

  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(stopArrivalsProvider(stopId)).value ?? const [];
    if (rows.length <= 2) return Text('Nothing else due soon', style: context.bb.text.caption);
    return ArrivalsList(rows: rows.skip(2).toList());
  }
}

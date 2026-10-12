import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/arrival/arrival_models.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/map_providers.dart';
import '../board/arrival_row_tile.dart';
import '../kit/kit.dart';

/// The next [max] arrivals at a stop, or a skeleton while the first load runs.
class ArrivalsPreview extends ConsumerWidget {
  const ArrivalsPreview({super.key, required this.stopId, this.max});

  final String stopId;
  final int? max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    if (rows == null) {
      return arrivals.hasError
          ? Text("Couldn't load arrivals", style: bb.text.caption)
          : BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: max ?? 3);
    }
    if (rows.isEmpty) return Text('No buses due soon', style: bb.text.caption);
    return ArrivalsList(rows: max == null ? rows : rows.take(max!).toList());
  }
}

/// A column of arrival rows. Live rows follow their bus on the map, which is
/// already on screen, so the sheet goes home and the follow camera takes over.
class ArrivalsList extends ConsumerWidget {
  const ArrivalsList({super.key, required this.rows});

  final List<ArrivalRow> rows;

  VoidCallback? _followable(WidgetRef ref, ArrivalRow a) {
    final vehicle = a.followableVehicle;
    if (vehicle == null) return null;
    return () {
      ref.read(homeSheetProvider.notifier).home();
      ref.read(followProvider.notifier).follow(vehicle);
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final a in rows) ArrivalRowTile(arrival: a, onTap: _followable(ref, a))],
      );
}

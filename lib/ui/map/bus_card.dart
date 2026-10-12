import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/map/bus_tracking_state.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/providers.dart';
import '../alerts/service_alert_card.dart';
import '../kit/kit.dart';
import 'map_layers.dart' show busLabel;

String delayText(int? schedDiffMins) => switch (schedDiffMins) {
      null => '',
      0 => 'on time',
      > 0 => '$schedDiffMins min early',
      _ => '${-schedDiffMins} min late',
    };

String agoText(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return s < 60 ? '$s s ago' : '${s ~/ 60} min ago';
}

BusTrackingState? _live(WidgetRef ref, String vehicleId) =>
    ref.watch(busTrackingStreamProvider).value?[vehicleId];

/// Bus card header (spec §3.3): route badge, destination, bus number, early/late.
class BusCardHeader extends ConsumerWidget {
  const BusCardHeader({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final bus = _live(ref, vehicleId);
    if (bus == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
        child: Text('This bus is no longer reporting', style: bb.text.body),
      );
    }
    // The live feed carries no headsign: take the destination from the trip.
    final tripId = bus.currentTripId;
    final headsign = bus.headsign.isNotEmpty
        ? bus.headsign
        : (tripId == null ? '' : ref.watch(gtfsRepositoryProvider).value?.tripsById[tripId]?.tripHeadsign ?? '');
    final delay = delayText(bus.schedDiffMins);
    final (pill, tone) = switch (bus.status) {
      BusStatus.active => ('Live', BBPillTone.live),
      BusStatus.offRoute => ('Off route', BBPillTone.warn),
      BusStatus.stale => ('Last seen ${agoText(DateTime.now().difference(bus.lastGpsTime))}', BBPillTone.neutral),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.m),
      child: Row(
        children: [
          RouteBadge.name(busLabel(bus)),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headsign.isNotEmpty ? 'to $headsign' : 'Route ${bus.routeNumber}',
                  style: bb.text.headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(delay.isEmpty ? 'Bus ${bus.vehicleId}' : 'Bus ${bus.vehicleId} · $delay', style: bb.text.caption),
              ],
            ),
          ),
          const SizedBox(width: BBSpace.s),
          Flexible(child: BBPill(label: pill, tone: tone, leadingDot: bus.status == BusStatus.active, wrap: true)),
        ],
      ),
    );
  }
}

/// Bus card body: any route alert, then a collapsed "Technical details"
/// section (speed, heading, last GPS update, map delay).
class BusCardBody extends ConsumerStatefulWidget {
  const BusCardBody({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  ConsumerState<BusCardBody> createState() => _BusCardBodyState();
}

class _BusCardBodyState extends ConsumerState<BusCardBody> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final bus = _live(ref, widget.vehicleId);
    if (bus == null) return const SizedBox.shrink();
    final alerts = ref
            .watch(serviceUpdatesProvider)
            .value
            ?.activeAlertsAt(DateTime.now())
            .where((a) => a.appliesTo(routeIds: {'${bus.routeNumber}'}))
            .toList() ??
        const [];
    final delay = ref.read(busTrackRendererProvider)?.currentDelayFor(bus.vehicleId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alerts.isNotEmpty) ...[
            ServiceAlertCard(alert: alerts.first, compact: true, onTap: () => context.push('/alerts')),
            const SizedBox(height: BBSpace.m),
          ],
          BBButton(
            label: 'Follow',
            icon: BBIcons.bus,
            expand: true,
            onPressed: () {
              ref.read(homeSheetProvider.notifier).home();
              ref.read(followProvider.notifier).follow(widget.vehicleId);
            },
          ),
          const SizedBox(height: BBSpace.m),
          BBPressable(
            onTap: () => setState(() => _open = !_open),
            semanticLabel: _open ? 'Technical details, expanded' : 'Technical details, collapsed',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BBSpace.s),
              child: Row(
                children: [
                  Expanded(child: Text('Technical details', style: bb.text.label)),
                  Icon(_open ? BBIcons.chevronDown : BBIcons.chevronRight, size: 16, color: bb.colors.muted),
                ],
              ),
            ),
          ),
          if (_open) ...[
            _Detail(label: 'Speed', value: '${bus.speedKmh.round()} km/h'),
            _Detail(label: 'Heading', value: '${bus.heading.round()}°'),
            _Detail(label: 'Last GPS update', value: agoText(DateTime.now().difference(bus.lastGpsTime))),
            if (delay != null) _Detail(label: 'Drawn behind live by', value: '${delay.inSeconds} s'),
          ],
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BBSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: bb.text.caption)),
          const SizedBox(width: BBSpace.m),
          Flexible(child: Text(value, style: bb.text.label, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

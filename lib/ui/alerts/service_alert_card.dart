import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../data/gtfs/gtfs_repository.dart';
import '../../data/realtime/service_alert_models.dart';
import '../kit/kit.dart';

/// One service alert. [compact] is the single-line-ish variant used on the
/// board and map sheets; [onTap] adds a chevron.
class ServiceAlertCard extends StatelessWidget {
  const ServiceAlertCard({
    super.key,
    required this.alert,
    this.stopNames = const {},
    this.compact = false,
    this.onTap,
  });

  final ServiceAlert alert;
  final Map<String, String> stopNames;
  final bool compact;
  final VoidCallback? onTap;

  static BBPillTone toneOf(ServiceAlert a) {
    if (a.severity == ServiceAlertSeverity.severe || a.effect == ServiceAlertEffect.noService) {
      return BBPillTone.danger;
    }
    if (a.effect == ServiceAlertEffect.detour ||
        a.effect == ServiceAlertEffect.significantDelays ||
        a.severity == ServiceAlertSeverity.warning) {
      return BBPillTone.warn;
    }
    return BBPillTone.brand;
  }

  static IconData iconOf(ServiceAlert a) => switch (a.effect) {
        ServiceAlertEffect.detour => BBIcons.detour,
        ServiceAlertEffect.noService => BBIcons.noService,
        ServiceAlertEffect.reducedService => BBIcons.reducedService,
        ServiceAlertEffect.significantDelays => BBIcons.schedule,
        ServiceAlertEffect.stopMoved => BBIcons.stopMoved,
        ServiceAlertEffect.accessibilityIssue => BBIcons.accessible,
        ServiceAlertEffect.additionalService => BBIcons.additionalService,
        _ => BBIcons.alerts,
      };

  static String? periodLabel(ServiceAlert a, DateTime now) {
    if (a.activePeriods.isEmpty) return null;
    final starts = a.activePeriods.map((p) => p.start).whereType<DateTime>();
    final ends = a.activePeriods.map((p) => p.end).whereType<DateTime>().toList()..sort();
    final format = DateFormat('MMM d, h:mm a');
    final nextStart = starts.where((s) => s.isAfter(now)).firstOrNull;
    if (nextStart != null) return 'Starts ${format.format(nextStart)}';
    if (ends.isNotEmpty) return 'Until ${format.format(ends.last)}';
    return 'Active now';
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final tone = toneOf(alert);
    final title = alert.header.isNotEmpty ? alert.header : alert.effect.label;
    final routes = alert.routeIds.toList()..sort(GtfsRepository.compareRouteNames);
    final period = compact ? null : periodLabel(alert, DateTime.now());

    return BBCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? BBSpace.m : BBSpace.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BBIconTile(icon: iconOf(alert), tone: tone, size: compact ? 34 : 42),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: compact ? 2 : null,
                      overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
                      style: compact ? bb.text.label.copyWith(fontSize: 14) : bb.text.headline,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: BBSpace.s),
                    Icon(BBIcons.chevronRight, size: 20, color: bb.colors.muted),
                  ],
                ]),
                const SizedBox(height: 5),
                Wrap(spacing: 6, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  // The pill would just repeat the title when the title is the effect.
                  if (title != alert.effect.label) BBPill(label: alert.effect.label, tone: tone),
                  for (final route in routes)
                    RouteBadge.name(route, size: RouteBadgeSize.compact),
                  for (final stop in alert.stopIds)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 230),
                      child: BBPill(
                        label: stopNames[stop] == null ? 'Stop $stop' : '${stopNames[stop]} · $stop',
                        tone: BBPillTone.brand,
                        wrap: true,
                      ),
                    ),
                ]),
                if (!compact && alert.description.isNotEmpty) ...[
                  const SizedBox(height: BBSpace.m),
                  Text(alert.description, style: bb.text.body.copyWith(color: bb.colors.muted)),
                ],
                if (period != null) ...[
                  const SizedBox(height: BBSpace.m),
                  Row(children: [
                    Icon(BBIcons.schedule, size: 14, color: bb.colors.muted),
                    const SizedBox(width: 6),
                    Flexible(child: Text(period, style: bb.text.caption)),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

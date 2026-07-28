import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/realtime/service_alert_models.dart';

class ServiceAlertCard extends StatelessWidget {
  final ServiceAlert alert;
  final Map<String, String> stopNames;
  final bool compact;
  final VoidCallback? onTap;

  const ServiceAlertCard({
    super.key,
    required this.alert,
    this.stopNames = const {},
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _alertColor(theme, alert);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 34 : 42,
                height: compact ? 34 : 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _alertIcon(alert),
                  size: compact ? 19 : 23,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            alert.header.isNotEmpty
                                ? alert.header
                                : alert.effect.label,
                            maxLines: compact ? 2 : null,
                            overflow: compact
                                ? TextOverflow.ellipsis
                                : TextOverflow.visible,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 14 : 16,
                            ),
                          ),
                        ),
                        if (onTap != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _AlertChip(label: alert.effect.label, color: color),
                        for (final route in _sortedRouteIds(alert.routeIds))
                          _AlertChip(
                            label: 'Route $route',
                            color: theme.colorScheme.primary,
                          ),
                        for (final stop in alert.stopIds)
                          _AlertChip(
                            label: stopNames[stop] == null
                                ? 'Stop $stop'
                                : '${stopNames[stop]} · $stop',
                            color: theme.colorScheme.secondary,
                          ),
                      ],
                    ),
                    if (!compact && alert.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        alert.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.78,
                          ),
                        ),
                      ),
                    ],
                    if (!compact && _periodLabel(alert) != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.42,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _periodLabel(alert)!,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.52,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _sortedRouteIds(Set<String> routes) {
    final result = routes.toList();
    result.sort((a, b) {
      final aNumber = int.tryParse(a);
      final bNumber = int.tryParse(b);
      if (aNumber != null && bNumber != null) {
        return aNumber.compareTo(bNumber);
      }
      return a.compareTo(b);
    });
    return result;
  }

  String? _periodLabel(ServiceAlert alert) {
    if (alert.activePeriods.isEmpty) return null;
    final starts = alert.activePeriods
        .map((period) => period.start)
        .whereType<DateTime>()
        .toList();
    final ends = alert.activePeriods
        .map((period) => period.end)
        .whereType<DateTime>()
        .toList();
    final now = DateTime.now();
    final nextStart = starts.where((start) => start.isAfter(now)).firstOrNull;
    if (nextStart != null) {
      return 'Starts ${DateFormat('MMM d, h:mm a').format(nextStart)}';
    }
    if (ends.isNotEmpty) {
      ends.sort();
      return 'Until ${DateFormat('MMM d, h:mm a').format(ends.last)}';
    }
    return 'Active now';
  }
}

class _AlertChip extends StatelessWidget {
  final String label;
  final Color color;

  const _AlertChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _alertColor(ThemeData theme, ServiceAlert alert) {
  if (alert.severity == ServiceAlertSeverity.severe ||
      alert.effect == ServiceAlertEffect.noService) {
    return theme.colorScheme.error;
  }
  if (alert.effect == ServiceAlertEffect.detour ||
      alert.effect == ServiceAlertEffect.significantDelays ||
      alert.severity == ServiceAlertSeverity.warning) {
    return theme.brightness == Brightness.light
        ? const Color(0xFFE66A00)
        : const Color(0xFFFFB74D);
  }
  return theme.colorScheme.primary;
}

IconData _alertIcon(ServiceAlert alert) => switch (alert.effect) {
  ServiceAlertEffect.detour => Icons.alt_route,
  ServiceAlertEffect.noService => Icons.block,
  ServiceAlertEffect.reducedService => Icons.remove_circle_outline,
  ServiceAlertEffect.significantDelays => Icons.schedule,
  ServiceAlertEffect.stopMoved => Icons.wrong_location_outlined,
  ServiceAlertEffect.accessibilityIssue => Icons.accessible,
  ServiceAlertEffect.additionalService => Icons.add_road,
  _ => Icons.campaign_outlined,
};

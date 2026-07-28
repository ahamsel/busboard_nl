import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/gtfs/gtfs_models.dart';
import '../../state/providers.dart';
import '../alerts/service_alert_card.dart';

class StopBottomSheet extends ConsumerWidget {
  final StopInfo stop;

  const StopBottomSheet({super.key, required this.stop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedId = ref.watch(settingsProvider).selectedStopId;
    final isSelected = stop.stopId == selectedId;
    final stopAlerts =
        ref
            .watch(serviceUpdatesProvider)
            .value
            ?.activeAlertsAt(DateTime.now())
            .where(
              (alert) =>
                  alert.appliesTo(routeIds: const {}, stopId: stop.stopId),
            )
            .toList() ??
        const [];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    theme.dividerTheme.color ??
                    theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_bus,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.stopName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Stop #${stop.stopId}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (stopAlerts.isNotEmpty) ...[
            const SizedBox(height: 14),
            ServiceAlertCard(
              alert: stopAlerts.first,
              stopNames: {stop.stopId: stop.stopName},
              compact: true,
              onTap: () {
                Navigator.pop(context);
                context.go('/alerts');
              },
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/board/${stop.stopId}');
                  },
                  icon: const Icon(Icons.departure_board, size: 18),
                  label: const Text('View Arrivals'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: isSelected
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.star, size: 18),
                        label: const Text('Selected'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () {
                          ref
                              .read(settingsProvider.notifier)
                              .setSelectedStop(stop.stopId);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.star_outline, size: 18),
                        label: const Text('Set as Stop'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

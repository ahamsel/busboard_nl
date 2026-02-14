import 'package:flutter/material.dart';
import '../../domain/map/bus_tracking_state.dart';

class BusBottomSheet extends StatelessWidget {
  final BusTrackingState bus;

  const BusBottomSheet({super.key, required this.bus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 52,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${bus.routeNumber}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bus.headsign.isNotEmpty ? bus.headsign : 'Route ${bus.routeNumber}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Bus ${bus.vehicleId}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: bus.status),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _InfoChip(label: 'Speed', value: '${bus.observations.last.speed.round()} km/h'),
              const SizedBox(width: 12),
              _InfoChip(label: 'Heading', value: '${bus.smoothedHeading.round()}°'),
              const SizedBox(width: 12),
              _InfoChip(
                label: 'Updated',
                value: _timeAgo(bus.lastUpdateTime),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}

class _StatusBadge extends StatelessWidget {
  final BusStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      BusStatus.active => ('ACTIVE', const Color(0xFF4FC3F7)),
      BusStatus.stopped => ('STOPPED', const Color(0xFFFFB74D)),
      BusStatus.stale => ('STALE', const Color(0xFF9E9E9E)),
      BusStatus.offRoute => ('OFF ROUTE', const Color(0xFFEF5350)),
      BusStatus.backtracking => ('BACKTRACK', const Color(0xFFFFB74D)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../domain/arrival/arrival_models.dart';

/// Single row on the arrival board showing one departure.
class ArrivalRowTile extends StatelessWidget {
  final ArrivalRow arrival;

  const ArrivalRowTile({super.key, required this.arrival});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Route number badge
          Container(
            width: 52,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                arrival.routeShortName,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Headsign + live status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  arrival.headsign,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 14.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    // Scheduled time
                    Text(
                      arrival.scheduledDisplay,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Live badge
                    if (arrival.isLive) ...[
                      const SizedBox(width: 8),
                      _LiveBadge(status: arrival.liveStatus),
                    ],
                    if (arrival.isLive && arrival.vehicleNumber != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Bus ${arrival.vehicleNumber}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Countdown
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                arrival.countdownText,
                style: TextStyle(
                  color: _countdownColor(arrival.minutesAway, theme),
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  letterSpacing: -0.3,
                ),
              ),
              if (arrival.isLive &&
                  arrival.predictedTime != null &&
                  arrival.scheduledTime != arrival.predictedTime)
                Text(
                  'sched ${arrival.scheduledDisplay}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 10.5,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _countdownColor(int minutes, ThemeData theme) {
    if (minutes <= 2) return const Color(0xFFEF5350); // Red — imminent
    if (minutes <= 5) return const Color(0xFFFFB74D); // Orange — soon
    if (minutes <= 10) return theme.colorScheme.secondary; // Green — coming
    return Colors.white.withValues(alpha: 0.7); // Default
  }
}

/// LIVE badge with status indicator.
class _LiveBadge extends StatelessWidget {
  final LiveStatus? status;

  const _LiveBadge({this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            status?.label ?? 'LIVE',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Color get _statusColor {
    switch (status) {
      case LiveStatus.ahead:
        return const Color(0xFF81C784); // Green
      case LiveStatus.onTime:
        return const Color(0xFF4FC3F7); // Blue
      case LiveStatus.behind:
        return const Color(0xFFFFB74D); // Orange
      case null:
        return const Color(0xFF4FC3F7);
    }
  }
}

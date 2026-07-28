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
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
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
                    // Stop-specific Metrobus prediction status.
                    if (arrival.isEnhanced) ...[
                      _StopPredictionBadge(isRealtime: arrival.isLive),
                      const SizedBox(width: 4),
                    ],
                    // Fleet-derived live status when no stop prediction exists.
                    if (arrival.isLive && !arrival.isEnhanced) ...[
                      _LiveBadge(status: arrival.liveStatus),
                    ],
                    if (arrival.routeRun != null ||
                        (arrival.isLive && arrival.vehicleNumber != null)) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            if (arrival.routeRun != null) arrival.routeRun!,
                            if (arrival.isLive && arrival.vehicleNumber != null)
                              'Bus ${arrival.vehicleNumber}',
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (arrival.isLive &&
                    arrival.currentLocation?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Near ${arrival.currentLocation}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Countdown + expected arrival time
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
              const SizedBox(height: 1),
              Text(
                arrival.isLive && arrival.predictedTime != null
                    ? 'exp ${arrival.displayTime.toDisplayString()}'
                    : arrival.scheduledDisplay,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (arrival.isLive &&
                  arrival.predictedTime != null &&
                  arrival.scheduledTime != arrival.predictedTime)
                Text(
                  'sched ${arrival.scheduledDisplay}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    fontSize: 10,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _countdownColor(int minutes, ThemeData theme) {
    final isLight = theme.brightness == Brightness.light;
    if (minutes <= 2) {
      return isLight ? const Color(0xFFD32F2F) : const Color(0xFFEF5350); // Red
    }
    if (minutes <= 5) {
      return isLight
          ? const Color(0xFFF57C00)
          : const Color(0xFFFFB74D); // Orange
    }
    if (minutes <= 10) return theme.colorScheme.secondary; // Green
    return theme.colorScheme.onSurface.withValues(alpha: 0.7); // Default
  }
}

/// Explicitly distinguishes Metrobus predictions from schedule-only rows.
class _StopPredictionBadge extends StatelessWidget {
  final bool isRealtime;

  const _StopPredictionBadge({required this.isRealtime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final color = isRealtime
        ? (isLight ? const Color(0xFF7B1FA2) : const Color(0xFFCE93D8))
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);

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
            isRealtime ? 'PRED' : 'SCHEDULE',
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
}

/// LIVE badge with status indicator.
class _LiveBadge extends StatelessWidget {
  final LiveStatus? status;

  const _LiveBadge({this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(theme);

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

  Color _statusColor(ThemeData theme) {
    final isLight = theme.brightness == Brightness.light;
    switch (status) {
      case LiveStatus.ahead:
        return isLight
            ? const Color(0xFF2E7D32)
            : const Color(0xFF81C784); // Green
      case LiveStatus.onTime:
        return isLight
            ? const Color(0xFF0277BD)
            : const Color(0xFF4FC3F7); // Blue
      case LiveStatus.behind:
        return isLight
            ? const Color(0xFFF57C00)
            : const Color(0xFFFFB74D); // Orange
      case null:
        return isLight ? const Color(0xFF0277BD) : const Color(0xFF4FC3F7);
    }
  }
}

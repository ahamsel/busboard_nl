import 'package:flutter/widgets.dart';

import '../../data/gtfs/gtfs_time.dart';
import '../../domain/arrival/arrival_models.dart';
import '../kit/kit.dart';

/// One departure on the Board: route badge · destination + status · minutes.
class ArrivalRowTile extends StatelessWidget {
  const ArrivalRowTile({
    super.key,
    required this.arrival,
    this.onTap,
    this.action,
  });

  final ArrivalRow arrival;

  /// Starts following this row's bus; null leaves the row inert.
  final VoidCallback? onTap;

  /// A trailing control with its own semantics (the alert bell).
  final Widget? action;

  /// Minutes at or below which the countdown uses the `soon` colour.
  static const int soonThresholdMinutes = 5;

  /// Largest share of the row the minutes column may take, so large text scales
  /// make its lines wrap instead of pushing the row past the card edge.
  static const double _maxTrailingShare = 0.45;

  /// Plain-words status pill for a row (spec §6.2).
  static (String, BBPillTone) statusOf(ArrivalRow a) {
    if (a.isEnhanced) {
      return a.isLive
          ? ('Live', BBPillTone.live)
          : ('Scheduled', BBPillTone.neutral);
    }
    if (a.isLive) {
      return switch (a.liveStatus) {
        LiveStatus.ahead => ('Early', BBPillTone.live),
        LiveStatus.behind => ('Late', BBPillTone.warn),
        LiveStatus.onTime => ('On time', BBPillTone.live),
        null => ('Live', BBPillTone.live),
      };
    }
    return ('Scheduled', BBPillTone.neutral);
  }

  /// One sentence for screen readers, e.g. "Route 29 Signal Hill Rd, live, 4 minutes,
  /// expected 09:55" (the expected time is spoken only for live rows with a prediction).
  static String semanticsLabel(ArrivalRow a, {required bool use24h}) {
    final (status, _) = statusOf(a);
    final when = a.minutesAway <= 0
        ? 'now'
        : a.minutesAway == 1
        ? '1 minute'
        : '${a.minutesAway} minutes';
    final expected = a.isLive && a.predictedTime != null
        ? ', expected ${BBTime.clock(a.displayTime.totalSeconds, use24h: use24h)}'
        : '';
    return 'Route ${a.routeShortName} ${a.headsign}, ${status.toLowerCase()}, $when$expected';
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final a = arrival;
    final use24h = BBTime.use24h(context);
    String clock(GtfsTime t) => BBTime.clock(t.totalSeconds, use24h: use24h);
    final (status, tone) = statusOf(a);
    final meta = [
      if (a.routeRun != null) a.routeRun!,
      if (a.isLive && a.vehicleNumber != null) 'Bus ${a.vehicleNumber}',
    ].join(' · ');
    final showPredicted = a.isLive && a.predictedTime != null;
    final timeLine = showPredicted
        ? 'exp ${clock(a.displayTime)}'
        : clock(a.scheduledTime);
    final showSched = showPredicted && a.scheduledTime != a.predictedTime;
    final soon = a.minutesAway <= soonThresholdMinutes;

    final content = LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          RouteBadge.name(a.routeShortName),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.headsign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bb.text.headline,
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    BBPill(
                      label: status,
                      tone: tone,
                      leadingDot: tone == BBPillTone.live,
                    ),
                    if (meta.isNotEmpty) Text(meta, style: bb.text.caption),
                  ],
                ),
                if (a.isLive && (a.currentLocation?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Near ${a.currentLocation}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: bb.text.caption,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: BBSpace.m),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: box.maxWidth * _maxTrailingShare,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The number rolls as it counts down (spec §3.2).
                BBRollingText(
                  a.minutesAway <= 0 ? 'Now' : '${a.minutesAway}',
                  style: bb.text.minutes.copyWith(
                    color: soon ? bb.colors.soon : bb.colors.ink,
                  ),
                ),
                if (a.minutesAway > 0) Text('min', style: bb.text.minutesUnit),
                const SizedBox(height: 2),
                Text(timeLine, style: bb.text.caption),
                if (showSched)
                  Text(
                    'sched ${clock(a.scheduledTime)}',
                    style: bb.text.caption.copyWith(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: bb.colors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    // A row becoming "Now" swells once and its card edge glows brand (spec §3.2).
    return BBNowPulse(
      active: a.minutesAway <= 0,
      child: BBCard(
        onTap: onTap,
        // The content below carries the tap and label; the card adds no second node.
        exposeSemantics: false,
        child: Row(
          children: [
            Expanded(
              // The content's own semantics replace the card's, so the tap is
              // restated here; the action stays outside so it keeps its own.
              child: Semantics(
                label: semanticsLabel(a, use24h: use24h),
                excludeSemantics: true,
                button: onTap != null ? true : null,
                onTap: onTap,
                onTapHint: onTap == null ? null : 'follow bus ${a.vehicleNumber} on the map',
                child: content,
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

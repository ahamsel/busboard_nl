import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import '../../data/gtfs/gtfs_time.dart';
import '../../data/gtfs/headsign.dart';
import '../../domain/arrival/arrival_models.dart';
import '../kit/kit.dart';

/// One departure on the Board: route badge · destination + status · minutes. A live row that can be followed shows a
/// Follow pill in its status line: a cue only, since a tap anywhere on the row follows the bus.
class ArrivalRowTile extends StatelessWidget {
  const ArrivalRowTile({
    super.key,
    required this.arrival,
    this.onTap,
    this.onExplain,
    this.action,
  });

  final ArrivalRow arrival;

  /// Starts following this row's bus, from a tap anywhere on the row (the Follow pill included). Null for a row with no
  /// bus to follow.
  final VoidCallback? onTap;

  /// A tap on a row with no bus to follow ([onTap] null): the caller says why ([whyNotFollowable]). Null leaves such a
  /// row inert.
  final VoidCallback? onExplain;

  /// A trailing control with its own semantics (the alert bell).
  final Widget? action;

  /// The Follow pill (visual only: the row is the target).
  static const followKey = ValueKey('arrival-follow');

  /// What a scheduled row's tap says.
  static const notLiveYet = "No bus on this trip yet. You can follow it once it's live.";

  /// What a live row with no bus number says: the row shows Live, so "no bus yet" would contradict it.
  static const noNumberYet = "This bus isn't sharing its number yet, so it can't be followed.";

  /// What a tap on a row with no bus to follow does, for TalkBack.
  static const explainHint = "hear why this bus can't be followed yet";

  /// Why a row has no bus to follow, for its toast: a live row is missing only its bus number.
  static String whyNotFollowable(ArrivalRow a) => a.isLive ? noNumberYet : notLiveYet;

  /// What the row says of its follow: VoiceOver's hint (TalkBack says the tap hint instead).
  static String followLabel(String vehicle) => 'Follow bus $vehicle on the map';

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
    return 'Route ${a.routeShortName} ${readableHeadsign(a.headsign)}, ${status.toLowerCase()}, $when$expected';
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final a = arrival;
    final use24h = BBTime.use24h(context);
    String clock(GtfsTime t) => BBTime.clock(t.totalSeconds, use24h: use24h);
    final (status, tone) = statusOf(a);
    final vehicle = a.vehicleNumber;
    // The pill names the bus, so the plain "Bus 2134" goes.
    final followable = onTap != null && a.isLive && vehicle != null && vehicle.isNotEmpty;
    final meta = [
      if (a.routeRun != null) a.routeRun!,
      if (a.isLive && vehicle != null && !followable) 'Bus $vehicle',
    ].join(' · ');
    final showPredicted = a.isLive && a.predictedTime != null;
    final timeLine = showPredicted
        ? 'exp ${clock(a.displayTime)}'
        : clock(a.scheduledTime);
    final showSched = showPredicted && a.scheduledTime != a.predictedTime;
    final soon = a.minutesAway <= soonThresholdMinutes;
    final tap = onTap ?? onExplain;

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
                  readableHeadsign(a.headsign),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bb.text.headline,
                ),
                const SizedBox(height: 3),
                // At large text the pill wraps under the status rather than truncate.
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
                    if (followable) _FollowPill(vehicle: vehicle),
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
                Text(
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
    return BBCard(
      onTap: tap,
      // The content below carries the tap and label; the card adds no second node.
      exposeSemantics: false,
      child: Row(
        children: [
          Expanded(
            // The content's own semantics replace the card's, so the tap is
            // restated here; the action stays outside so it keeps its own.
            // The Follow pill is part of this one node: its words are the hint.
            child: Semantics(
              label: semanticsLabel(a, use24h: use24h),
              excludeSemantics: true,
              button: tap != null ? true : null,
              onTap: tap,
              onTapHint: onTap != null
                  ? 'follow bus ${a.vehicleNumber} on the map'
                  : onExplain != null
                      ? explainHint
                      : null,
              hint: followable && defaultTargetPlatform == TargetPlatform.iOS ? followLabel(vehicle) : null,
              child: content,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// "Follow 2134": `brandSoft` with `brandInk` text, at the status pill's height so the row keeps 1.4.1's height. It
/// is a cue, not a button: the row around it does the follow.
class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.vehicle});

  final String vehicle;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final ink = bb.colors.brandInk;
    return DecoratedBox(
      key: ArrivalRowTile.followKey,
      decoration: BoxDecoration(color: bb.colors.brandSoft, borderRadius: BorderRadius.circular(BBRadius.pill)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BBSpace.s, vertical: 3),
        // One paragraph, icon and words, so on a narrow row it wraps instead of overflowing.
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(BBIcons.bus, size: 14, color: ink),
              ),
              TextSpan(text: ' Follow $vehicle'),
            ],
          ),
          style: bb.text.caption.copyWith(color: ink, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

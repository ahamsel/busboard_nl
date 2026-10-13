import 'package:flutter/widgets.dart';

import '../../domain/map/follow_tracker.dart';
import '../../domain/map/route_geometry.dart';
import '../kit/kit.dart';
import 'bus_card.dart';
import 'map_layers.dart';

/// The toast that says why a follow ended; null for an arrival, which the
/// card has already announced.
String? followEndMessage(FollowEnd why, String vehicleId, String? yourStopName) => switch (why) {
      FollowEnd.arrived => null,
      FollowEnd.passedYourStop => 'Bus $vehicleId has passed ${yourStopName ?? 'your stop'}',
      FollowEnd.tripEnded => 'Bus $vehicleId has finished its trip',
      FollowEnd.lostContact => 'Lost contact with bus $vehicleId',
      FollowEnd.notFound => "Bus $vehicleId isn't reporting its position",
    };

String stopsToGoText(int? stopsTo, String? yourStopName) {
  final name = yourStopName ?? 'your stop';
  return switch (stopsTo) {
    null => "Your stop isn't on this trip",
    0 => 'Next stop: $name',
    1 => '1 stop to $name',
    _ => '$stopsTo stops to $name',
  };
}

/// Scheduled departure shifted by the current delay (a positive diff is
/// early, so a late bus pushes the time later); "sched" when the delay is
/// unknown. Empty when the timetable has no time for the stop.
String etaText(TripStop stop, int? schedDiffMins, {required bool use24h}) {
  final s = stop.departureSeconds;
  if (s == null) return '';
  final clock = BBTime.clock(s - (schedDiffMins ?? 0) * 60, use24h: use24h);
  return schedDiffMins == null ? '$clock sched' : clock;
}

/// The snapshot's indices, made safe for [FollowSnapshot.stops]: a shape
/// change can leave them pointing past the list.
({int bus, int? yours}) _safeIndices(FollowSnapshot s) {
  final n = s.stops.length;
  final yours = s.yourStopIndex;
  return (
    bus: s.busIndex.clamp(-1, n - 1),
    yours: yours != null && yours >= 0 && yours < n ? yours : null,
  );
}

/// Follow card at peek (spec §3.5): who, where to, how far from your stop,
/// a stop strip, and the two actions.
class FollowCardHeader extends StatelessWidget {
  const FollowCardHeader({
    super.key,
    required this.snapshot,
    required this.yourStopName,
    required this.minutesToYourStop,
    required this.tripHeadsign,
    this.routeLabel,
    required this.onStop,
    required this.onSeeAll,
    this.actionsFirst = false,
    this.actionsKey,
    this.alertAction,
  });

  final FollowSnapshot snapshot;
  final String? yourStopName;
  final int? minutesToYourStop;

  /// The followed trip's destination, from [FollowSnapshot.tripId]. Used once
  /// the bus has arrived, when the bus itself may already be on its next trip.
  final String? tripHeadsign;

  /// The followed trip's route, for the badge and strip colour. Falls back to
  /// the bus's own route, which may be its next trip's once it has arrived.
  final String? routeLabel;
  final VoidCallback onStop;
  final VoidCallback onSeeAll;

  /// Puts the two actions right under the title row, before the stops-to-go
  /// line and the strip. The map sets it when the whole header is taller than
  /// the peek can be (large text, small screens), so both actions stay in the
  /// peek. The header is just as tall either way, so measuring it is stable.
  final bool actionsFirst;

  /// On the column holding the actions, so the map can keep them in the peek.
  final Key? actionsKey;

  /// The arrival-alert bell, at the end of the title row until the bus arrives.
  final Widget? alertAction;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final bus = snapshot.bus;
    final id = snapshot.vehicleId;
    if (bus == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Finding bus $id…', style: bb.text.headline),
            const SizedBox(height: BBSpace.m),
            KeyedSubtree(
              key: actionsKey,
              child: BBButton(label: 'Stop following', kind: BBButtonKind.quiet, expand: true, onPressed: onStop),
            ),
          ],
        ),
      );
    }
    final arrived = snapshot.arrived;
    final route = routeLabel ?? busLabel(bus);
    // After arrival the bus may be on its next trip: its headsign and delay
    // no longer describe the trip being followed.
    final headsign = arrived || bus.headsign.isEmpty ? tripHeadsign : bus.headsign;
    final delay = arrived ? '' : delayText(bus.schedDiffMins);
    final subtitle = snapshot.stale
        ? 'Bus $id · Last seen ${agoText(snapshot.lastSeenAgo ?? Duration.zero)}'
        : (delay.isEmpty ? 'Bus $id' : 'Bus $id · $delay');
    // The stop arrived at, from the trip: your stop may have been changed
    // during the linger.
    final arrivedAt = _safeIndices(snapshot).yours;
    final arrivedName = arrivedAt == null ? yourStopName : snapshot.stops[arrivedAt].name;
    final line = arrived ? 'Arrived at ${arrivedName ?? 'your stop'}' : stopsToGoText(snapshot.stopsToYourStop, yourStopName);
    final minutes = minutesToYourStop;
    final actions = Column(
      key: actionsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BBButton(label: 'See all stops', expand: true, onPressed: onSeeAll),
        const SizedBox(height: BBSpace.s),
        BBButton(label: 'Stop following', kind: BBButtonKind.quiet, expand: true, onPressed: onStop),
      ],
    );
    final minutesLabel = minutes == null || arrived ? null : (minutes <= 0 ? 'Now' : '$minutes min');
    final minutesStyle =
        bb.text.headline.copyWith(color: minutes != null && minutes <= 5 ? bb.colors.soon : bb.colors.ink);
    final minutesText = minutes == null || minutesLabel == null
        ? null
        : Semantics(
            label: switch (minutes) {
              <= 0 => 'Due now',
              1 => '1 minute to your stop',
              _ => '$minutes minutes to your stop',
            },
            excludeSemantics: true,
            child: Text(minutesLabel, style: minutesStyle),
          );
    final bell = arrived ? null : alertAction;
    final title = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headsign == null || headsign.isEmpty ? 'Route $route' : 'to $headsign',
            style: bb.text.headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(subtitle, style: bb.text.caption),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.m),
      child: LayoutBuilder(builder: (context, constraints) {
        // Large text or a narrow screen: the minutes and the bell get their own row under the title, rather
        // than squeezing it.
        final below = (minutesText != null || bell != null) &&
            _titleShare(context, constraints.maxWidth, minutesLabel, minutesStyle, bell != null) < 0.4;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RouteBadge.name(route),
                const SizedBox(width: BBSpace.m),
                title,
                if (!below && (minutesText != null || bell != null)) ...[
                  const SizedBox(width: BBSpace.s),
                  ?minutesText,
                  ?bell,
                ],
              ],
            ),
            if (below) ...[
              const SizedBox(height: BBSpace.s),
              Row(children: [Expanded(child: minutesText ?? const SizedBox.shrink()), ?bell]),
            ],
            if (actionsFirst) ...[const SizedBox(height: BBSpace.m), actions],
            const SizedBox(height: BBSpace.s),
            // Its text changes only with the stop count, so a screen reader
            // announces it at most once per stop.
            Semantics(liveRegion: true, label: line, excludeSemantics: true, child: Text(line, style: bb.text.body)),
            const SizedBox(height: BBSpace.s),
            ExcludeSemantics(child: _StopStrip(snapshot: snapshot, routeLabel: route)),
            if (!actionsFirst) ...[const SizedBox(height: BBSpace.m), actions],
          ],
        );
      }),
    );
  }

  /// The share of the title row beside the badge that the title would keep next to the minutes and the bell.
  /// [width] is the whole row's.
  static double _titleShare(BuildContext context, double width, String? minutes, TextStyle style, bool bell) {
    if (!width.isFinite || width <= 0) return 1;
    final scaler = MediaQuery.textScalerOf(context);
    var trailing = BBSpace.s + (bell ? _bellWidth : 0);
    if (minutes != null) {
      final painter = TextPainter(
        text: TextSpan(text: minutes, style: style),
        textScaler: scaler,
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      trailing += painter.width;
      painter.dispose();
    }
    final beside = width - RouteBadge.largeSide * scaler.scale(1).clamp(1.0, RouteBadge.maxScale) - BBSpace.m;
    return beside <= 0 ? 0 : (beside - trailing) / beside;
  }

  /// A `BBIconButton`'s tap target.
  static const double _bellWidth = 44;
}

/// The last stop driven, the bus, then the stops ahead up to your stop: at
/// most seven stop markers, and nothing after your stop's star. When your stop
/// is further than the cap it replaces the last dot; once the bus is at your
/// stop the strip ends there, the bus beside the star. With your stop not on
/// the trip it shows the next stops and no star.
class _StopStrip extends StatelessWidget {
  const _StopStrip({required this.snapshot, required this.routeLabel});

  final FollowSnapshot snapshot;
  final String routeLabel;

  static const int maxMarkers = 7;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final stops = snapshot.stops;
    if (stops.isEmpty) return const SizedBox.shrink();
    final idx = _safeIndices(snapshot);
    final routeLine = RoutePalette.ofName(routeLabel).lineFor(bb.brightness);
    final yours = idx.yours;
    final atOrPast = yours != null && yours <= idx.bus;

    // The stop marker behind the bus. At your stop that is the one before it,
    // since your stop's own marker (the star) closes the strip.
    final behind = idx.bus == yours ? idx.bus - 1 : idx.bus;
    final driven = behind >= 0 ? behind : null;
    final room = maxMarkers - (driven == null ? 0 : 1) - (atOrPast ? 1 : 0);
    final List<int> ahead;
    if (atOrPast) {
      ahead = const [];
    } else {
      final last = yours == null ? idx.bus + room : (yours < idx.bus + room ? yours : idx.bus + room);
      ahead = [for (var i = idx.bus + 1; i < stops.length && i <= last; i++) i];
      if (yours != null && ahead.isNotEmpty && ahead.last != yours) ahead[ahead.length - 1] = yours;
    }

    Widget dot(int i) {
      if (i == yours) return Icon(BBIcons.star, key: const ValueKey('strip-star'), size: 16, color: bb.brandEdge);
      final passed = i <= idx.bus;
      return Container(
        key: ValueKey('strip-dot-$i'),
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: passed ? bb.colors.muted : null,
          border: passed ? null : Border.all(color: routeLine, width: 2),
          shape: BoxShape.circle,
        ),
      );
    }

    Widget connector(Color color) => Expanded(child: Container(height: 2, color: color));
    final children = <Widget>[
      if (driven != null) ...[dot(driven), connector(bb.colors.line)],
      BBGlyph(BBGlyphKind.bus, key: const ValueKey('strip-bus'), size: 18, color: routeLine),
      if (atOrPast) ...[
        const SizedBox(width: BBSpace.xs),
        dot(yours),
      ] else
        for (final i in ahead) ...[connector(routeLine), dot(i)],
    ];
    return SizedBox(height: 20, child: Row(children: children));
  }
}

/// See all stops (spec §3.5): from the bus to the end of its trip, ETAs from
/// the timetable shifted by the current delay; your stop emphasised. When your
/// stop isn't on this trip, the next six stops.
class FollowCardBody extends StatelessWidget {
  const FollowCardBody({super.key, required this.snapshot});

  final FollowSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final all = snapshot.stops;
    final idx = _safeIndices(snapshot);
    final start = idx.bus + 1;
    final upcoming = start >= all.length ? const <TripStop>[] : all.sublist(start);
    final shown = idx.yours == null ? upcoming.take(6).toList() : upcoming;
    // After arrival the bus may be on its next trip: its delay isn't ours.
    final diff = snapshot.arrived ? null : snapshot.bus?.schedDiffMins;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BBSectionHeader(title: 'Stops'),
          for (var k = 0; k < shown.length; k++)
            _TimelineRow(
              stop: shown[k],
              eta: etaText(shown[k], diff, use24h: BBTime.use24h(context)),
              yours: start + k == idx.yours,
            ),
          if (shown.isEmpty) Text('No more stops on this trip', style: bb.text.caption),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.stop, required this.eta, required this.yours});

  final TripStop stop;
  final String eta;
  final bool yours;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final style = yours ? bb.text.label.copyWith(color: bb.colors.brandInk) : bb.text.body;
    return Semantics(
      label: [stop.name, if (yours) 'your stop', if (eta.isNotEmpty) eta.replaceFirst(' sched', ' scheduled')].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BBSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 20, child: yours ? Icon(BBIcons.star, size: 16, color: bb.brandEdge) : null),
            const SizedBox(width: BBSpace.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stop.name, style: style),
                  if (yours) Text('Your stop', style: bb.text.caption),
                ],
              ),
            ),
            const SizedBox(width: BBSpace.s),
            Text(eta, style: bb.text.caption),
          ],
        ),
      ),
    );
  }
}

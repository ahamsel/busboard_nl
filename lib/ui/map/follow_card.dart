import 'package:flutter/widgets.dart';

import '../../domain/map/follow_tracker.dart';
import '../../domain/map/route_geometry.dart';
import '../kit/kit.dart';
import 'bus_card.dart';
import 'map_layers.dart';

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
String etaText(TripStop stop, int? schedDiffMins) {
  final s = stop.departureSeconds;
  if (s == null) return '';
  final shifted = (s - (schedDiffMins ?? 0) * 60) % 86400;
  final h = shifted ~/ 3600;
  final m = (shifted % 3600) ~/ 60;
  final clock = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
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
            BBButton(label: 'Stop following', kind: BBButtonKind.quiet, expand: true, onPressed: onStop),
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
    final line = arrived ? 'Arrived at ${yourStopName ?? 'your stop'}' : stopsToGoText(snapshot.stopsToYourStop, yourStopName);
    final minutes = minutesToYourStop;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RouteBadge.name(route),
              const SizedBox(width: BBSpace.m),
              Expanded(
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
              ),
              if (minutes != null && !arrived) ...[
                const SizedBox(width: BBSpace.s),
                Semantics(
                  label: switch (minutes) {
                    <= 0 => 'Due now',
                    1 => '1 minute to your stop',
                    _ => '$minutes minutes to your stop',
                  },
                  excludeSemantics: true,
                  child: Text(
                    minutes <= 0 ? 'Now' : '$minutes min',
                    style: bb.text.headline.copyWith(color: minutes <= 5 ? bb.colors.soon : bb.colors.ink),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: BBSpace.s),
          // Its text changes only with the stop count, so a screen reader
          // announces it at most once per stop.
          Semantics(liveRegion: true, label: line, excludeSemantics: true, child: Text(line, style: bb.text.body)),
          const SizedBox(height: BBSpace.s),
          ExcludeSemantics(child: _StopStrip(snapshot: snapshot, routeLabel: route)),
          const SizedBox(height: BBSpace.m),
          BBButton(label: 'See all stops', expand: true, onPressed: onSeeAll),
          const SizedBox(height: BBSpace.s),
          BBButton(label: 'Stop following', kind: BBButtonKind.quiet, expand: true, onPressed: onStop),
        ],
      ),
    );
  }
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
    final routeLine = RoutePalette.ofName(routeLabel).line;
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
      if (i == yours) return Icon(BBIcons.star, key: const ValueKey('strip-star'), size: 16, color: bb.colors.brand);
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
              eta: etaText(shown[k], diff),
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
            SizedBox(width: 20, child: yours ? Icon(BBIcons.star, size: 16, color: bb.colors.brand) : null),
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

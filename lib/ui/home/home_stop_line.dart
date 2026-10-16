import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../data/realtime/service_alert_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/first_bus.dart';
import '../../state/home_tab_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../kit/kit.dart';

/// The alert the stop line's ⚠ names: of the [active] alerts touching [stopId] or its [routes], the one with the
/// highest [ServiceAlert.priority] (feed order breaks a tie). Information and Additional service are not warnings,
/// and an agency-wide alert the agency marks as info is not about this stop: none of them marks it.
ServiceAlert? stopLineAlert(Iterable<ServiceAlert> active, {required Set<String> routes, required String stopId}) {
  ServiceAlert? best;
  for (final a in active) {
    if (a.effect == ServiceAlertEffect.noEffect || a.effect == ServiceAlertEffect.additionalService) continue;
    if (!a.appliesTo(routeIds: routes, stopId: stopId)) continue;
    final agencyWide = a.targets.every((t) => t.routeId == null && t.stopId == null && t.tripId == null);
    if (agencyWide && a.severity == ServiceAlertSeverity.info) continue;
    if (best == null || a.priority > best.priority) best = a;
  }
  return best;
}

/// What the stop line shows (spec 2026-10-14 §3.2).
enum StopLineKind {
  /// The next bus: its route and minutes ("Now" at 0 or less), live or scheduled.
  next,

  /// No bus within the three hours the arrivals cover, and the next one is not a day's first.
  none,

  /// Night, or before the day's service: the first bus's time.
  firstBus,

  /// The first load is still running.
  loading,

  /// The departures could not be loaded (offline, or a feed error).
  offline,
}

/// The stop line's content for one moment: everything [HomeStopLine] draws and says.
@immutable
class StopLineInfo {
  const StopLineInfo({
    required this.stopName,
    required this.kind,
    this.route,
    this.minutes,
    this.live = false,
    this.firstBus,
    this.firstBusDay,
    this.updatedAt,
    this.alertEffect,
  });

  /// [arrivals] is the stop's departures as loaded; [firstBus] is asked only when none are due. [now] dates the first
  /// bus: one two or more days away (over a weekend or a holiday) names its weekday.
  factory StopLineInfo.resolve({
    required String stopName,
    required AsyncValue<List<ArrivalRow>> arrivals,
    required DateTime? Function() firstBus,
    DateTime? now,
    DateTime? updatedAt,
    String? alertEffect,
  }) {
    StopLineInfo of(StopLineKind kind, {ArrivalRow? next, DateTime? first}) => StopLineInfo(
      stopName: stopName,
      kind: kind,
      route: next?.routeShortName,
      minutes: next?.minutesAway,
      live: next?.isLive ?? false,
      firstBus: first,
      firstBusDay: first == null || now == null ? null : firstBusDayLabel(first, now),
      updatedAt: updatedAt,
      alertEffect: alertEffect,
    );
    if (arrivals.hasError) return of(StopLineKind.offline);
    final rows = arrivals.value;
    if (rows == null) return of(StopLineKind.loading);
    if (rows.isNotEmpty) return of(StopLineKind.next, next: rows.first);
    final first = firstBus();
    return first == null ? of(StopLineKind.none) : of(StopLineKind.firstBus, first: first);
  }

  final String stopName;
  final StopLineKind kind;
  final String? route;
  final int? minutes;
  final bool live;
  final DateTime? firstBus;

  /// The first bus's weekday ("Mon") when it is two or more days away; null later today or tomorrow.
  final String? firstBusDay;

  /// [first]'s weekday ("Mon") when it is two or more calendar days after [now], else null: later today needs no
  /// day, and tomorrow's first bus is the next morning's (the line has no "tomorrow" form).
  static String? firstBusDayLabel(DateTime first, DateTime now) {
    final days =
        DateTime.utc(first.year, first.month, first.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    return days >= 2 ? DateFormat('EEE').format(first) : null;
  }

  /// When the departures last loaded, for the offline note.
  final DateTime? updatedAt;

  /// The label of an active alert's effect on the stop or its routes ("Detour"), or null.
  final String? alertEffect;

  bool get now => kind == StopLineKind.next && (minutes ?? 0) <= 0;

  /// The words after the stop name for the kinds without a route: "No buses for a while", "First bus 6:28 AM",
  /// "Offline · updated 9:42 AM". Null for [StopLineKind.next] and [StopLineKind.loading].
  ///
  /// [spoken] is for screen readers: the weekday in full ("Monday"), where the screen shows "Mon".
  String? note({required bool use24h, bool spoken = false}) => switch (kind) {
    StopLineKind.none => 'No buses for a while',
    StopLineKind.firstBus =>
      'First bus ${firstBusDay == null ? '' : '${spoken ? DateFormat('EEEE').format(firstBus!) : firstBusDay} '}'
          '${BBTime.of(firstBus!, use24h: use24h)}',
    StopLineKind.offline =>
      updatedAt == null ? 'Offline' : 'Offline · updated ${BBTime.of(updatedAt!, use24h: use24h)}',
    StopLineKind.next || StopLineKind.loading => null,
  };

  /// What a screen reader says (spec 2026-10-14 §3.2).
  String semantics({required bool use24h}) {
    final head = 'Your stop, $stopName.${alertEffect == null ? '' : ' $alertEffect affects this stop.'}';
    final status = live ? 'live' : 'scheduled';
    return switch (kind) {
      StopLineKind.loading => '$head Loading',
      StopLineKind.next when now => '$head Route $route arriving now, $status. Open board',
      StopLineKind.next =>
        '$head Route $route in ${minutes == 1 ? '1 minute' : '$minutes minutes'}, $status. Open board',
      StopLineKind.offline =>
        '$head ${updatedAt == null ? 'Offline' : 'Offline, updated ${BBTime.of(updatedAt!, use24h: use24h)}'}. Open board',
      _ => '$head ${note(use24h: use24h, spoken: true)}. Open board',
    };
  }
}

/// The bar's second row (spec 2026-10-14 §3.1, §3.2): your stop and its next bus, one tap from its Board. With no
/// stop chosen it is "Choose your stop", which pulls the sheet up to the nearby stops ([onChooseStop]) or, with none
/// to show, opens a stop search.
class HomeStopLine extends ConsumerWidget {
  const HomeStopLine({super.key, this.onChooseStop});

  final VoidCallback? onChooseStop;

  static const lineKey = ValueKey('home-stop-line');

  /// At least this tall at any text size (spec §3.1).
  static const double minHeight = 48;

  /// The most of the line a note may take; the stop name gets the rest and truncates first.
  static const double _maxNoteShare = 0.6;

  /// What the stop name keeps however large the text: its first letters and an ellipsis.
  static const double _minName = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
    final stop = stopId == null ? null : ref.watch(stopInfoProvider(stopId));
    if (stop == null) {
      return BBPressable(
        key: lineKey,
        semanticLabel: 'Choose your stop',
        onTap: () {
          // Nearby stops to pick from: pull up to them. None (location off or refused, or nothing near): a search for
          // the stop number on the pole (spec 2026-10-12 §4.4).
          final nearby = ref.read(nearestStopsProvider);
          final none = nearby.hasError || (nearby.hasValue && nearby.value!.isEmpty);
          if (none) {
            context.push('/search?pickStop=1');
          } else {
            onChooseStop?.call();
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: Row(
            children: [
              Icon(BBIcons.nearMe, size: 18, color: bb.brandEdge),
              const SizedBox(width: BBSpace.s),
              Flexible(
                child: Text('Choose your stop', style: bb.text.headline.copyWith(color: bb.colors.brandInk)),
              ),
              const SizedBox(width: BBSpace.xs),
              Icon(BBIcons.chevronRight, size: 18, color: bb.colors.brandInk),
            ],
          ),
        ),
      );
    }

    final use24h = BBTime.use24h(context);
    final arrivals = ref.watch(stopArrivalsProvider(stop.stopId));
    final updatedAt = ref.watch(stopArrivalsUpdatedAtProvider.select((m) => m[stop.stopId]));
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final updates = ref.watch(serviceUpdatesProvider).value;
    final routes = repo?.routeShortNamesForStop(stop.stopId).toSet() ?? const <String>{};
    final alert = updates == null
        ? null
        : stopLineAlert(updates.activeAlertsAt(DateTime.now()), routes: routes, stopId: stop.stopId);
    final now = ref.read(plannerClockProvider)();
    final info = StopLineInfo.resolve(
      stopName: stop.stopName,
      arrivals: arrivals,
      updatedAt: updatedAt,
      alertEffect: alert?.effect.label,
      firstBus: () => repo == null ? null : firstBusAfter(repo, stop.stopId, now),
      now: now,
    );

    final muted = bb.text.body.copyWith(color: bb.colors.muted);
    return BBPressable(
      key: lineKey,
      semanticLabel: info.semantics(use24h: use24h),
      onTap: () => ref.read(homeTabProvider.notifier).showBoard(stop.stopId),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: LayoutBuilder(
          builder: (context, box) {
            // The star, its gap and the alert mark are fixed; the name keeps [_minName]; the rest may go to the time.
            final tailMax = math.max(0.0, box.maxWidth - 26 - (info.alertEffect == null ? 0 : 22) - _minName);
            return Row(
              children: [
                Icon(BBIcons.star, size: 18, color: bb.brandEdge),
                const SizedBox(width: BBSpace.s),
                // The name gives way first: the time after it never truncates (spec §3.2).
                Flexible(
                  child: Text(stop.stopName, style: bb.text.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (info.alertEffect != null) ...[
                  const SizedBox(width: BBSpace.xs),
                  Icon(
                    BBIcons.warning,
                    key: const ValueKey('home-stop-line-alert'),
                    size: 18,
                    color: bb.colors.warnInk,
                  ),
                ],
                switch (info.kind) {
                  // Shrinks (never truncates) only when even a 40 pt name would not leave it room: huge text on a
                  // narrow phone.
                  StopLineKind.next => ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: tailMax),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(' · ', style: muted),
                          RouteBadge.name(info.route!, size: RouteBadgeSize.compact),
                          const SizedBox(width: BBSpace.s),
                          // Rolling minutes (visual refresh §3.2), at title size: large text, so "Now" in `soon`
                          // meets 3:1.
                          BBRollingText(
                            info.now ? 'Now' : '${info.minutes}',
                            style: bb.text.title.copyWith(
                              color: info.now ? bb.colors.soon : bb.colors.ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (!info.now) Text(' min', style: bb.text.headline),
                          if (info.live) ...[
                            const SizedBox(width: BBSpace.s),
                            BBLiveDot(color: bb.colors.live, size: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                  StopLineKind.loading => const Padding(
                    padding: EdgeInsets.only(left: BBSpace.s),
                    child: SizedBox(width: 64, child: BBSkeleton(kind: BBSkeletonKind.line, count: 1)),
                  ),
                  // A note wraps onto a second line rather than lose its end (the bar grows with it).
                  _ => ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.min(tailMax, box.maxWidth * _maxNoteShare)),
                    child: Text(' · ${info.note(use24h: use24h)}', style: muted),
                  ),
                },
              ],
            );
          },
        ),
      ),
    );
  }
}

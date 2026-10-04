import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../state/providers.dart';
import '../../data/realtime/metrobus_mobile_api.dart';
import '../../data/realtime/service_alert_models.dart';
import '../../data/realtime/timetrack_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/arrival_service.dart';
import '../alerts/service_alert_card.dart';
import '../kit/kit.dart';
import 'arrival_row_tile.dart';

/// Arrival board screen for a selected stop.
///
/// Shows upcoming departures with scheduled and live data.
/// Auto-refreshes based on configured interval (foreground only).
class ArrivalBoardScreen extends ConsumerStatefulWidget {
  final String stopId;

  const ArrivalBoardScreen({super.key, required this.stopId});

  @override
  ConsumerState<ArrivalBoardScreen> createState() => _ArrivalBoardScreenState();
}

class _ArrivalBoardScreenState extends ConsumerState<ArrivalBoardScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  DateTime _lastUpdate = DateTime.now();
  List<ArrivalRow> _arrivals = [];
  bool _loading = true;
  bool _liveAvailable = false;
  bool _refreshInProgress = false;
  String? _liveIssue;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshData();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshData();
      _startTimer();
    } else {
      _refreshTimer?.cancel();
    }
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    final settings = ref.read(settingsProvider);
    _refreshTimer = Timer.periodic(
      Duration(seconds: settings.refreshIntervalSeconds),
      (_) => _refreshData(),
    );
  }

  Future<void> _refreshData() async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;

    try {
      final repoAsync = ref.read(gtfsRepositoryProvider);
      final repo = repoAsync.asData?.value;
      if (repo == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Schedule data not loaded';
          });
        }
        return;
      }

      final service = ArrivalService(repo);

      // Try live data while preserving the difference between a valid empty
      // response and an upstream failure.
      List<TimeTrackVehicle>? liveVehicles;
      bool liveOk = false;
      String? liveIssue;
      try {
        final api = ref.read(timetrackApiProvider);
        final result = await api.fetchVehiclesResult();
        if (result.succeeded) {
          liveVehicles = result.vehicles;
          liveOk = liveVehicles.isNotEmpty;
          if (!liveOk) {
            liveIssue = 'No live vehicles';
          }
        } else {
          liveIssue = 'Live feed error';
        }
      } catch (_) {
        liveIssue = 'Live feed error';
      }

      // Try Metrobus's official stop-specific prediction endpoint.
      List<MetrobusDeparture>? stopPredictions;
      try {
        final mobileApi = ref.read(metrobusMobileApiProvider);
        final result = await mobileApi.fetchDeparturesResult(widget.stopId);
        stopPredictions = result.departures;
      } catch (_) {}

      final arrivals = service.getUpcomingArrivals(
        stopId: widget.stopId,
        now: DateTime.now(),
        liveVehicles: liveVehicles,
        stopPredictions: stopPredictions,
      );

      if (mounted) {
        setState(() {
          _arrivals = arrivals;
          _loading = false;
          _liveAvailable = liveOk;
          _liveIssue = liveIssue;
          _lastUpdate = DateTime.now();
          _error = null;
        });
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Restart timer when refresh interval changes in settings
    ref.listen<int>(settingsProvider.select((s) => s.refreshIntervalSeconds), (
      prev,
      next,
    ) {
      if (prev != next) _startTimer();
    });
    // The schedule may finish loading after the first refresh ran (e.g. a deep
    // link straight to the board); load the departures as soon as it arrives.
    ref.listen<AsyncValue<Object?>>(gtfsRepositoryProvider, (prev, next) {
      if (next.hasValue && prev?.hasValue != true) _refreshData();
    });

    final bb = context.bb;
    final stopInfo = ref.watch(stopInfoProvider(widget.stopId));
    final stopName = stopInfo?.stopName ?? 'Stop ${widget.stopId}';
    final relevantAlerts = _relevantAlerts(
      ref.watch(serviceUpdatesProvider).value,
    );
    final updated = DateFormat('HH:mm:ss').format(_lastUpdate);
    // The live region carries only the state, so assistive tech announces
    // live <-> schedule transitions but not every refresh timestamp.
    final checking = _loading && _error == null;
    final stateText = checking
        ? 'Checking live data…'
        : _liveAvailable
            ? 'Live'
            : '${_liveIssue ?? 'Live unavailable'} · showing schedule';

    // The alert sits at the top of the scrolling list, not in the fixed header:
    // at large text the fixed header plus an alert card would fill a small
    // screen and leave the departures no room.
    final alertBlock = relevantAlerts.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.xs, BBSpace.screen, BBSpace.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ServiceAlertCard(
                alert: relevantAlerts.first,
                stopNames: stopInfo == null ? const {} : {widget.stopId: stopInfo.stopName},
                compact: true,
                onTap: () => context.go('/alerts'),
              ),
              if (relevantAlerts.length > 1)
                BBButton(
                  label:
                      '${relevantAlerts.length - 1} more relevant ${relevantAlerts.length == 2 ? "alert" : "alerts"}',
                  kind: BBButtonKind.quiet,
                  onPressed: () => context.go('/alerts'),
                ),
            ]),
          );

    return BBScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.s, BBSpace.xs, 0),
            child: Row(children: [
              // Pill and Change share the width the 44 pt settings button leaves,
              // so large text ellipsises them instead of overflowing the row.
              Expanded(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BBPill(
                    label: 'STOP ${widget.stopId}',
                    background: bb.colors.ink,
                    foreground: bb.colors.bg,
                  ),
                ),
              ),
              Flexible(
                flex: 2,
                child: BBButton(label: 'Change', kind: BBButtonKind.quiet, onPressed: () => context.pop()),
              ),
              BBIconButton(
                icon: BBIcons.settings,
                semanticLabel: 'Settings',
                onPressed: () => context.push('/settings'),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.xs, BBSpace.screen, 0),
            child: Semantics(
              header: true,
              child: Text(stopName, maxLines: 2, overflow: TextOverflow.ellipsis, style: bb.text.display),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.xs, BBSpace.screen, BBSpace.s),
            child: Row(children: [
              BBGlyph(BBGlyphKind.liveDot, size: 12, color: _liveAvailable ? bb.colors.live : bb.colors.muted),
              const SizedBox(width: BBSpace.s),
              Flexible(
                child: Semantics(
                  // Silent while the first refresh is in flight so assistive
                  // tech never hears a provisional negative state.
                  liveRegion: !checking,
                  child: Text(stateText, style: bb.text.caption),
                ),
              ),
              if (_liveAvailable) Text(' · updated $updated', style: bb.text.caption),
            ]),
          ),
          Expanded(child: BBRefresh(onRefresh: _refreshData, semanticLabel: 'Departures', child: _buildArrivalsList(context, alertBlock))),
        ],
      ),
    );
  }

  List<ServiceAlert> _relevantAlerts(ServiceUpdates? updates) {
    if (updates == null) return const [];
    final routes = _arrivals.map((arrival) => arrival.routeShortName).toSet();
    final trips = _arrivals.map((arrival) => arrival.tripId).toSet();
    return updates
        .activeAlertsAt(DateTime.now())
        .where(
          (alert) => alert.appliesTo(
            routeIds: routes,
            stopId: widget.stopId,
            tripIds: trips,
          ),
        )
        .toList();
  }

  Widget _buildArrivalsList(BuildContext context, Widget? alertBlock) {
    final bottom = BBNavBar.reservedHeight(context) + BBSpace.l;

    // Every state is a scrollable list so pull-to-refresh always works.
    Widget centered(Widget child) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottom),
          children: [?alertBlock, const SizedBox(height: 64), Center(child: child)],
        );

    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottom),
        children: [
          ?alertBlock,
          const Padding(
            padding: EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.s, BBSpace.screen, 0),
            child: BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 5, label: 'Loading departures...'),
          ),
        ],
      );
    }
    if (_error != null) {
      return centered(BBEmptyState(icon: BBIcons.error, tone: BBEmptyTone.error, title: _error!));
    }
    if (_arrivals.isEmpty) {
      return centered(const BBEmptyState(
        icon: BBIcons.schedule,
        title: 'No upcoming departures',
        message: 'There are no scheduled departures\nfrom this stop right now.',
      ));
    }
    final leading = alertBlock == null ? 0 : 1;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottom),
      itemCount: leading + _arrivals.length,
      itemBuilder: (_, index) {
        if (index < leading) return alertBlock;
        return Padding(
          padding: EdgeInsets.fromLTRB(BBSpace.screen, index == 0 ? BBSpace.s : 0, BBSpace.screen, BBSpace.s),
          child: ArrivalRowTile(arrival: _arrivals[index - leading]),
        );
      },
    );
  }
}

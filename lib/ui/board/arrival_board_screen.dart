import 'dart:async';
import 'package:flutter/material.dart';
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

    final theme = Theme.of(context);
    final stopInfo = ref.watch(stopInfoProvider(widget.stopId));
    final relevantAlerts = _relevantAlerts(
      ref.watch(serviceUpdatesProvider).value,
    );
    final timeFormat = DateFormat('HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text(
              stopInfo?.stopName ?? 'Stop ${widget.stopId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'Stop #${widget.stopId}',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: theme.colorScheme.primary,
        child: Column(
          children: [
            // Status bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(
                    color:
                        theme.dividerTheme.color ??
                        theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Updated timestamp
                  Icon(
                    Icons.update,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Updated ${timeFormat.format(_lastUpdate)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  // Status indicators
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_liveAvailable) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.light
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFF81C784),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'GPS FEED',
                          style: TextStyle(
                            color: theme.brightness == Brightness.light
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFF81C784),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ] else
                        Text(
                          _liveIssue ?? 'Live unavailable',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            if (relevantAlerts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Column(
                  children: [
                    ServiceAlertCard(
                      alert: relevantAlerts.first,
                      stopNames: stopInfo == null
                          ? const {}
                          : {widget.stopId: stopInfo.stopName},
                      compact: true,
                      onTap: () => context.go('/alerts'),
                    ),
                    if (relevantAlerts.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: TextButton(
                          onPressed: () => context.go('/alerts'),
                          child: Text(
                            '${relevantAlerts.length - 1} more relevant '
                            '${relevantAlerts.length == 2 ? "alert" : "alerts"}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // Arrivals list
            Expanded(child: _buildArrivalsList(theme)),
          ],
        ),
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

  Widget _buildArrivalsList(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error.withValues(alpha: 0.9),
            ),
            const SizedBox(height: 16),
            Text(_error!, style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    if (_arrivals.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.schedule,
                  size: 56,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No upcoming departures',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'There are no scheduled departures\nfrom this stop right now.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _arrivals.length,
      separatorBuilder: (context, i) => Divider(
        height: 1,
        indent: 82,
        color:
            theme.dividerTheme.color ??
            theme.colorScheme.onSurface.withValues(alpha: 0.06),
      ),
      itemBuilder: (context, index) {
        return ArrivalRowTile(arrival: _arrivals[index]);
      },
    );
  }
}

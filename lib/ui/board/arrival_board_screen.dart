import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../state/providers.dart';
import '../../data/realtime/metrobus_mobile_api.dart';
import '../../data/realtime/timetrack_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/arrival_service.dart';
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
  bool _enhancedAvailable = false;
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

    // Try live data
    List<TimeTrackVehicle>? liveVehicles;
    bool liveOk = false;
    try {
      final api = ref.read(timetrackApiProvider);
      liveVehicles = await api.fetchVehicles();
      liveOk = liveVehicles.isNotEmpty;
    } catch (_) {}

    // Try enhanced predictions (scraped data)
    List<MetrobusDeparture>? scraped;
    bool enhancedOk = false;
    /* // TEMPORARILY DISABLED SCRAPING
    if (ref.read(settingsProvider).useEnhancedPredictions) {
      try {
        final mobileApi = ref.read(metrobusMobileApiProvider);
        final result = await mobileApi.fetchDepartures(widget.stopId);
        if (result.isNotEmpty) {
          scraped = result;
          enhancedOk = true;
        }
      } catch (_) {}
    }
    */

    final arrivals = service.getUpcomingArrivals(
      stopId: widget.stopId,
      now: DateTime.now(),
      liveVehicles: liveVehicles,
      scrapedDepartures: scraped,
    );

    if (mounted) {
      setState(() {
        _arrivals = arrivals;
        _loading = false;
        _liveAvailable = liveOk;
        _enhancedAvailable = enhancedOk;
        _lastUpdate = DateTime.now();
        _error = null;
      });
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
                      if (_enhancedAvailable) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.light
                                ? const Color(0xFF7B1FA2)
                                : const Color(0xFFCE93D8),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'ENHANCED',
                          style: TextStyle(
                            color: theme.brightness == Brightness.light
                                ? const Color(0xFF7B1FA2)
                                : const Color(0xFFCE93D8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
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
                          'LIVE',
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
                          'Live unavailable',
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

            // Arrivals list
            Expanded(child: _buildArrivalsList(theme)),
          ],
        ),
      ),
    );
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/realtime/service_alert_models.dart';
import '../../state/providers.dart';
import '../copy/legal_copy.dart';
import 'service_alert_card.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(serviceUpdatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: updates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _AlertsError(
          error: error.toString(),
          onRetry: () => ref.invalidate(serviceUpdatesProvider),
        ),
        data: (data) => _AlertsContent(
          updates: data,
          onRefresh: () async {
            ref.invalidate(serviceUpdatesProvider);
            await ref.read(serviceUpdatesProvider.future);
          },
        ),
      ),
    );
  }
}

class _AlertsContent extends ConsumerWidget {
  final ServiceUpdates updates;
  final Future<void> Function() onRefresh;

  const _AlertsContent({required this.updates, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final active = updates.activeAlertsAt(now);
    final upcoming = updates.alerts
        .where((alert) => !alert.isActiveAt(now))
        .toList();
    final repo = ref.watch(gtfsRepositoryProvider).asData?.value;
    final stopNames = <String, String>{
      for (final alert in updates.alerts)
        for (final stopId in alert.stopIds)
          if (repo?.stopsById[stopId] != null)
            stopId: repo!.stopsById[stopId]!.stopName,
    };

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _ServiceStatusCard(
            status: updates.serviceStatus,
            fetchedAt: updates.feedTimestamp ?? updates.fetchedAt,
          ),
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'Active now',
            count: active.length,
            color: active.isEmpty
                ? theme.colorScheme.secondary
                : theme.colorScheme.error,
          ),
          const SizedBox(height: 10),
          if (active.isEmpty)
            const _NoAlertsCard()
          else
            for (var i = 0; i < active.length; i++) ...[
              ServiceAlertCard(alert: active[i], stopNames: stopNames),
              if (i != active.length - 1) const SizedBox(height: 12),
            ],
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle(
              title: 'Upcoming',
              count: upcoming.length,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < upcoming.length; i++) ...[
              ServiceAlertCard(alert: upcoming[i], stopNames: stopNames),
              if (i != upcoming.length - 1) const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 18),
          Text(
            LegalCopy.footer,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceStatusCard extends StatelessWidget {
  final MetrobusServiceStatus? status;
  final DateTime fetchedAt;

  const _ServiceStatusCard({required this.status, required this.fetchedAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final operating = status?.serviceOperating;
    final color = operating == false
        ? theme.colorScheme.error
        : theme.colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status?.message.isNotEmpty == true
                      ? status!.message
                      : 'Metrobus service status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Updated ${DateFormat('h:mm:ss a').format(fetchedAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          if (status?.day.isNotEmpty == true)
            Text(
              status!.day,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SectionTitle({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoAlertsCard extends StatelessWidget {
  const _NoAlertsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No active service alerts.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertsError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _AlertsError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 14),
            Text(
              'Could not load service alerts',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

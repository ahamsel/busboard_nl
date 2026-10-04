import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/realtime/service_alert_models.dart';
import '../../state/providers.dart';
import '../copy/legal_copy.dart';
import '../kit/kit.dart';
import 'service_alert_card.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesAsync = ref.watch(serviceUpdatesProvider);
    return BBScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BBTopBar(
            title: 'Service alerts',
            large: true,
            actions: [
              BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () => context.push('/settings')),
            ],
          ),
          Expanded(
            child: updatesAsync.when(
              loading: () => const Center(child: BBLoading(label: 'Loading service alerts...')),
              error: (error, _) => Center(
                child: BBEmptyState(
                  icon: BBIcons.offline,
                  tone: BBEmptyTone.error,
                  title: 'Could not load service alerts',
                  message: error.toString(),
                  action: BBButton(
                    label: 'Retry',
                    icon: BBIcons.refresh,
                    onPressed: () => ref.invalidate(serviceUpdatesProvider),
                  ),
                ),
              ),
              data: (updates) => _AlertsContent(updates: updates),
            ),
          ),
        ],
      ),
    );
  }
}

bool _hasEnded(ServiceAlert a, DateTime now) =>
    a.activePeriods.isNotEmpty && a.activePeriods.every((p) => p.hasEndedBefore(now));

class _AlertsContent extends ConsumerWidget {
  const _AlertsContent({required this.updates});

  final ServiceUpdates updates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final now = DateTime.now();
    final active = updates.activeAlertsAt(now);
    final upcoming = updates.alerts.where((a) => !a.isActiveAt(now) && !_hasEnded(a, now)).toList();
    final repo = ref.watch(gtfsRepositoryProvider).asData?.value;
    final stopNames = <String, String>{
      if (repo != null)
        for (final alert in updates.alerts)
          for (final stopId in alert.stopIds)
            if (repo.stopsById[stopId] != null) stopId: repo.stopsById[stopId]!.stopName,
    };

    List<Widget> cards(List<ServiceAlert> alerts) => [
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0) const SizedBox(height: BBSpace.m),
            ServiceAlertCard(alert: alerts[i], stopNames: stopNames),
          ],
        ];

    return BBRefresh(
      onRefresh: () async {
        ref.invalidate(serviceUpdatesProvider);
        await ref.read(serviceUpdatesProvider.future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          BBSpace.screen, BBSpace.s, BBSpace.screen, BBNavBar.reservedHeight(context) + BBSpace.l),
        children: [
          _ServiceStatusCard(status: updates.serviceStatus, fetchedAt: updates.feedTimestamp ?? updates.fetchedAt),
          const SizedBox(height: BBSpace.xl),
          BBSectionHeader(
            title: 'Active now',
            count: active.length,
            countTone: active.isEmpty ? BBPillTone.live : BBPillTone.danger,
          ),
          const SizedBox(height: BBSpace.m),
          if (active.isEmpty)
            BBCard(
              padding: const EdgeInsets.all(BBSpace.xl),
              child: Row(children: [
                Icon(BBIcons.checkCircle, color: bb.colors.liveInk),
                const SizedBox(width: BBSpace.m),
                Expanded(child: Text('No active service alerts.', style: bb.text.body)),
              ]),
            )
          else
            ...cards(active),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: BBSpace.xxl),
            BBSectionHeader(title: 'Upcoming', count: upcoming.length),
            const SizedBox(height: BBSpace.m),
            ...cards(upcoming),
          ],
          const SizedBox(height: BBSpace.xl),
          Text(LegalCopy.footer, textAlign: TextAlign.center, style: bb.text.caption),
        ],
      ),
    );
  }
}

class _ServiceStatusCard extends StatelessWidget {
  const _ServiceStatusCard({required this.status, required this.fetchedAt});

  final MetrobusServiceStatus? status;
  final DateTime fetchedAt;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final stopped = status?.serviceOperating == false;
    final title = (status?.message.isNotEmpty ?? false) ? status!.message : 'Metrobus service status';
    return BBCard(
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: stopped ? bb.colors.dangerInk : bb.colors.live, shape: BoxShape.circle),
        ),
        const SizedBox(width: BBSpace.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: bb.text.headline),
            Text('Updated ${DateFormat('h:mm:ss a').format(fetchedAt)}', style: bb.text.caption),
          ]),
        ),
        if (status?.day.isNotEmpty ?? false)
          BBPill(label: status!.day, tone: stopped ? BBPillTone.danger : BBPillTone.live),
      ]),
    );
  }
}

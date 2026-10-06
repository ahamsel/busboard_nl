import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival_alerts/arrival_alert.dart';
import '../../state/arrival_alert_providers.dart';
import '../kit/kit.dart';
import 'lead_time_sheet.dart';

/// The bell on an arrival (spec §2.1). Nothing for a bus under 3 or over 60 minutes away.
class AlertBell extends ConsumerWidget {
  const AlertBell({super.key, required this.arrival, required this.stopId, required this.stopName});

  final ArrivalRow arrival;
  final String stopId;
  final String stopName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(arrivalAlertProvider).value;
    final active = current != null && current.stopId == stopId && current.tripId == arrival.tripId;
    if (!active && !canAlert(arrival)) return const SizedBox.shrink();
    final route = arrival.routeShortName;
    return BBIconButton(
      icon: active ? BBIcons.bellFill : BBIcons.bell,
      color: active ? context.bb.colors.liveInk : null,
      semanticLabel: active ? 'Alert set for route $route. Cancel alert' : 'Alert me before route $route arrives',
      onPressed: () => active ? _confirmCancel(context, ref) : _set(context, ref, current),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    // Read before the await: the Board may drop this row while the dialog is open.
    final controller = ref.read(arrivalAlertProvider.notifier);
    final yes = await BBDialog.show<bool>(
      context,
      title: 'Cancel your alert for route ${arrival.routeShortName}?',
      actions: const [
        BBDialogAction(label: 'Keep', value: false),
        BBDialogAction(label: 'Cancel alert', value: true, primary: true),
      ],
    );
    if (yes == true) await controller.cancel();
  }

  Future<void> _set(BuildContext context, WidgetRef ref, ArrivalAlert? current) async {
    final controller = ref.read(arrivalAlertProvider.notifier);
    if (current != null) {
      final replace = await BBDialog.show<bool>(
        context,
        title: 'Replace your alert for route ${current.routeShortName}?',
        actions: const [
          BBDialogAction(label: 'Keep', value: false),
          BBDialogAction(label: 'Replace', value: true, primary: true),
        ],
      );
      if (replace != true || !context.mounted) return;
    }
    final initial = await controller.lastLead();
    final explain = !await controller.permissionGranted();
    if (!context.mounted) return;
    final lead = await showLeadTimeSheet(context, arrival: arrival, initialLead: initial, explainPermission: explain);
    if (lead == null) return;
    final result = await controller.set(arrival, stopId: stopId, stopName: stopName, leadMinutes: lead);
    if (result == SetAlertResult.permissionDenied && context.mounted) {
      final open = await BBDialog.show<bool>(
        context,
        title: 'Alerts need notifications',
        message: 'Turn on notifications for BusBoard in Settings.',
        actions: const [
          BBDialogAction(label: 'Not now', value: false),
          BBDialogAction(label: 'Open settings', value: true, primary: true),
        ],
      );
      if (open == true) await Geolocator.openAppSettings();
    }
  }
}

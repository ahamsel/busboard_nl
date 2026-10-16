import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

/// Alerts (with the active count) and Settings, floating on the map (spec 2026-10-12 §3.1).
class MapButtons extends StatelessWidget {
  const MapButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return DecoratedBox(
      decoration: bb.mapControl(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AlertsButton(),
          Container(width: 28, height: 1, color: bb.colors.line),
          const SettingsButton(),
        ],
      ),
    );
  }
}

/// Opens Service alerts, with the number of active alerts on the bell: the same button on the map and in the Board's
/// header (spec 2026-10-15 §5).
class AlertsButton extends ConsumerWidget {
  const AlertsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final count = ref.watch(serviceUpdatesProvider).value?.activeAlertsAt(DateTime.now()).length ?? 0;
    final alertsLabel = count > 0 ? 'Alerts, $count active' : 'Alerts';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        BBIconButton(
          icon: BBIcons.alerts,
          semanticLabel: alertsLabel,
          onPressed: () => context.push('/alerts'),
        ),
        if (count > 0)
          Positioned(
            top: 4,
            right: 4,
            // The count grows with the text only so far: at large sizes it would cover the bell.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: bb.colors.dangerInk,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: bb.text.caption.copyWith(
                        color: bb.colors.surface,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens Settings: on the map and in the Board's header.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => BBIconButton(
        icon: BBIcons.settings,
        semanticLabel: 'Settings',
        onPressed: () => context.push('/settings'),
      );
}

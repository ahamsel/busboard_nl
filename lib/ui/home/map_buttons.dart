import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

/// Alerts (with the active count) and Settings, floating on the map (spec 2026-10-12 §3.1).
class MapButtons extends ConsumerWidget {
  const MapButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final count =
        ref
            .watch(serviceUpdatesProvider)
            .value
            ?.activeAlertsAt(DateTime.now())
            .length ??
        0;
    final alertsLabel = count > 0 ? 'Alerts, $count active' : 'Alerts';
    return DecoratedBox(
      decoration: bb.floating(radius: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
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
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
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
            ],
          ),
          Container(width: 28, height: 1, color: bb.colors.line),
          BBIconButton(
            icon: BBIcons.settings,
            semanticLabel: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

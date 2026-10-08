import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/arrival_alert_providers.dart';
import '../kit/kit.dart';

/// "Alert set · Route 10 · 5 min before · Cancel" at the top of the Board (spec §2.1).
class AlertStrip extends ConsumerWidget {
  const AlertStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(arrivalAlertProvider).value;
    if (a == null) return const SizedBox.shrink();
    final bb = context.bb;
    return BBCard(
      child: Row(children: [
        Icon(BBIcons.bellFill, size: 20, color: bb.colors.liveInk),
        const SizedBox(width: BBSpace.s),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text('Alert set · Route ${a.routeShortName} · ${a.leadMinutes} min before', style: bb.text.body),
          ),
        ),
        BBButton(
          label: 'Cancel',
          kind: BBButtonKind.quiet,
          onPressed: () => ref.read(arrivalAlertProvider.notifier).cancel(),
        ),
      ]),
    );
  }
}

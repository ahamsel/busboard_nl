import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/seen_flags.dart';
import '../kit/kit.dart';

/// The one-time tip under a stop's departures while one of them is live (spec 2026-10-14 §4.3). It goes for good once
/// the rider closes it or follows a bus (the home screen marks it then).
class FollowTip extends ConsumerWidget {
  const FollowTip({super.key});

  static const text = 'Tap a live bus to follow it on the map';
  static const closeKey = ValueKey('follow-tip-close');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(followTipSeenProvider).value != false) return const SizedBox.shrink();
    final bb = context.bb;
    return Row(
      children: [
        Icon(BBIcons.info, size: 18, color: bb.colors.muted),
        const SizedBox(width: BBSpace.s),
        Expanded(child: Text(text, style: bb.text.caption)),
        BBIconButton(
          key: closeKey,
          icon: BBIcons.close,
          size: 18,
          color: bb.colors.muted,
          semanticLabel: 'Hide this tip',
          onPressed: () => ref.read(followTipSeenProvider.notifier).markSeen(),
        ),
      ],
    );
  }
}

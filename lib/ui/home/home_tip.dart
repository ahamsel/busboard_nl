import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kit/kit.dart';

const _key = 'home_tip_seen.v1';
const homeTipText = 'Everything\'s on the map now: tap "Where to?" to plan, a stop for its buses, the bell for '
    'alerts. Your Board is still here: tap Open board, or pull your stop up.';

class HomeTipSeenNotifier extends AsyncNotifier<bool> {
  HomeTipSeenNotifier();

  /// Already seen, for tests.
  factory HomeTipSeenNotifier.seen() = _Seen;

  @override
  Future<bool> build() async =>
      await SharedPreferencesAsync().getBool(_key) ?? false;

  Future<void> dismiss() async {
    state = const AsyncData(true);
    await SharedPreferencesAsync().setBool(_key, true);
  }
}

class _Seen extends HomeTipSeenNotifier {
  @override
  Future<bool> build() async => true;
}

final homeTipSeenProvider = AsyncNotifierProvider<HomeTipSeenNotifier, bool>(
  HomeTipSeenNotifier.new,
);

/// The one-time "everything moved" tip (spec 2026-10-12 §3.7).
class HomeTip extends ConsumerWidget {
  const HomeTip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(homeTipSeenProvider).value != false) {
      return const SizedBox.shrink();
    }
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.only(bottom: BBSpace.s),
      child: DecoratedBox(
        decoration: bb.card(),
        child: Padding(
          padding: const EdgeInsets.all(BBSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(homeTipText, style: bb.text.body),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: BBButton(
                  label: 'Got it',
                  kind: BBButtonKind.quiet,
                  onPressed: () =>
                      ref.read(homeTipSeenProvider.notifier).dismiss(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

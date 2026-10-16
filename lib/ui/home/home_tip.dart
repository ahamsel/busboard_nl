import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kit/kit.dart';

const _key = 'home_tip_seen.v1';
// For riders upgrading from 1.4 (and new ones), on their first visit to the Map tab: where things are now that home
// has two tabs (spec 2026-10-15 §2). Shared by the phone's bar and the tablet panel, so it names no button only one
// of them has.
const homeTipText = 'Your buses are on the Board tab. Use the Map tab to see the map, plan a trip or follow a bus.';

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

/// The one-time tip on where things are (spec 2026-10-12 §3.7, reworded for the two tabs of spec 2026-10-15).
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
        decoration: BBSurfaceScope.cardOf(context),
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

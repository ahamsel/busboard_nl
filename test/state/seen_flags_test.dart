import 'package:busboard_nl/state/seen_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_alerts.dart';

void main() {
  setUp(useInMemoryAlertStore);

  test('a flag reads false until marked, then true, and stays true on the next start', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(barHintSeenProvider.future), isFalse);
    await c.read(barHintSeenProvider.notifier).markSeen();
    expect(c.read(barHintSeenProvider).value, isTrue);
    expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isTrue);
    final next = ProviderContainer();
    addTearDown(next.dispose);
    expect(await next.read(barHintSeenProvider.future), isTrue);
  });

  test('marking while the stored value is still being read keeps it marked', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(barHintSeenProvider.notifier).markSeen();
    expect(c.read(barHintSeenProvider).value, isTrue);
    expect(await c.read(barHintSeenProvider.future), isTrue);
  });

  test('the seen double is seen without reading the phone', () async {
    final c = ProviderContainer(overrides: [
      barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(barHintSeenProvider.future), isTrue);
    expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isNull);
  });
}

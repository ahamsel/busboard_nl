import 'package:busboard_nl/state/follow_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('follow holds one vehicle id; stop clears it', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(followProvider), isNull);
    c.read(followProvider.notifier).follow('2573');
    expect(c.read(followProvider), const FollowTarget('2573'));
    c.read(followProvider.notifier).follow('1311');
    expect(c.read(followProvider), const FollowTarget('1311'), reason: 'a new follow replaces the old one');
    c.read(followProvider.notifier).stop();
    expect(c.read(followProvider), isNull);
  });
}

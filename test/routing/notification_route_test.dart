import 'package:busboard_nl/routing/notification_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Board route from a notification is opened', () {
    final went = <String>[];
    expect(openNotificationRoute('/board/1150', went.add), isTrue);
    expect(went, ['/board/1150']);
  });

  test('anything else is ignored', () {
    final went = <String>[];
    for (final p in [null, '', '/', '/settings', '/board/', '/board/1150/x', 'board/1150', 'https://x.test/board/1']) {
      expect(openNotificationRoute(p, went.add), isFalse, reason: '$p');
    }
    expect(went, isEmpty);
  });
}

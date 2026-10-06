import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('the alert watcher is a specialUse foreground service with the spec subtype', () {
    expect(manifest, contains('android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"'));
    expect(manifest, contains('android:foregroundServiceType="specialUse"'));
    expect(manifest,
        contains('A live transit arrival alert the user starts; it ends when the bus arrives (90 min max)'));
    expect(manifest, contains('android:name="android.permission.POST_NOTIFICATIONS"'));
  });

  test('no dataSync, boot or exact-alarm permissions', () {
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_DATA_SYNC')));
    expect(manifest, isNot(contains('RECEIVE_BOOT_COMPLETED')));
    expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
  });

  test('the notification icon survives resource shrinking', () {
    expect(File('android/app/src/main/res/drawable/ic_notification.xml').existsSync(), isTrue);
    expect(File('android/app/src/main/res/raw/keep.xml').readAsStringSync(), contains('@drawable/ic_notification'));
  });
}

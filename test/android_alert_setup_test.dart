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

  test('no dataSync or exact-alarm permissions; flutter_foreground_task boot hooks are removed', () {
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_DATA_SYNC')));
    expect(manifest,
        contains('<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" tools:node="remove"/>'));
    expect(manifest,
        contains('<receiver android:name="com.pravera.flutter_foreground_task.service.RebootReceiver" tools:node="remove"/>'));
    expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
  });

  test('the notification icon survives resource shrinking', () {
    expect(File('android/app/src/main/res/drawable/ic_notification.xml').existsSync(), isTrue);
    expect(File('android/app/src/main/res/raw/keep.xml').readAsStringSync(), contains('@drawable/ic_notification'));
  });
}

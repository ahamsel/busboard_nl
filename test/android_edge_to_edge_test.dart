import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android 15+ (target SDK 35+) draws apps edge-to-edge. Play Console looks for
/// an explicit opt-in (`enableEdgeToEdge()`, i.e. `EdgeToEdge.enable`) so older
/// Android versions match; Flutter's own SystemUiMode.edgeToEdge uses
/// WindowCompat, which it does not count. These guard the native opt-in.
void main() {
  const activity = 'android/app/src/main/kotlin/com/ahamsel/busboard_nl/MainActivity.kt';

  test('MainActivity opts into edge-to-edge through androidx.activity', () {
    final src = File(activity).readAsStringSync();
    // enableEdgeToEdge() is an extension on ComponentActivity; FlutterActivity
    // is a plain Activity, FlutterFragmentActivity is a ComponentActivity.
    expect(src, contains('FlutterFragmentActivity'));
    expect(src, contains('import androidx.activity.enableEdgeToEdge'));
    final onCreate = src.indexOf('override fun onCreate');
    expect(onCreate, greaterThanOrEqualTo(0), reason: 'MainActivity overrides onCreate');
    final call = src.indexOf('enableEdgeToEdge()', onCreate);
    final superCall = src.indexOf('super.onCreate', onCreate);
    expect(call, greaterThan(onCreate));
    expect(call, lessThan(superCall), reason: 'edge-to-edge is enabled before the Flutter view is created');
  });

  test('release builds keep the edge-to-edge call site that Play scans for', () {
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();
    expect(rules, contains('-keep class androidx.activity.EdgeToEdge'));
  });

  test('Flutter side: edge-to-edge mode with transparent system bars', () {
    expect(File('lib/main.dart').readAsStringSync(), contains('SystemUiMode.edgeToEdge'));
    final scaffold = File('lib/ui/kit/bb_scaffold.dart').readAsStringSync();
    expect(scaffold, contains('statusBarColor: const Color(0x00000000)'));
    expect(scaffold, contains('systemNavigationBarColor: const Color(0x00000000)'));
  });
}

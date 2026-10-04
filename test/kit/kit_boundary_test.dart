import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Material/Cupertino widgets that must not appear in screen code.
final _forbidden = RegExp(
  r'\b(Scaffold|AppBar|NavigationBar|NavigationDestination|BottomNavigationBar|'
  r'FloatingActionButton|ListTile|Card|ElevatedButton|FilledButton|TextButton|'
  r'OutlinedButton|IconButton|SegmentedButton|Switch|SwitchListTile|Chip|FilterChip|'
  r'ChoiceChip|ActionChip|SnackBar|AlertDialog|showModalBottomSheet|showDialog|'
  r'RefreshIndicator|InkWell|Badge|Slider|Cupertino[A-Z]\w*)\b\s*[.(<]'
  r'|\bIcons\.',
);

/// Screens not yet rebuilt on the kit. Phase 2 removes entries as it
/// migrates each file; the list must only ever shrink.
const _legacyAllowList = {
  'lib/ui/alerts/alerts_screen.dart',
  'lib/ui/alerts/service_alert_card.dart',
  'lib/ui/board/arrival_board_screen.dart',
  'lib/ui/map/bus_bottom_sheet.dart',
  'lib/ui/map/map_screen.dart',
  'lib/ui/map/stop_bottom_sheet.dart',
  'lib/ui/settings/settings_screen.dart',
  'lib/ui/shell/app_shell.dart',
  'lib/ui/stop_picker/near_me_list.dart',
  'lib/ui/stop_picker/stop_id_entry.dart',
  'lib/ui/stop_picker/stop_picker_screen.dart',
};

void main() {
  final files = Directory('lib/ui')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((p) => !p.startsWith('lib/ui/kit/'))
      .toList()
    ..sort();

  List<String> violations(String path) {
    final lines = File(path).readAsLinesSync();
    return [
      for (var i = 0; i < lines.length; i++)
        if (!lines[i].trimLeft().startsWith('//') && _forbidden.hasMatch(lines[i]))
          '$path:${i + 1}: ${lines[i].trim()}',
    ];
  }

  test('screen code uses the kit, not Material/Cupertino widgets', () {
    final bad = [
      for (final f in files)
        if (!_legacyAllowList.contains(f)) ...violations(f),
    ];
    expect(bad, isEmpty, reason: 'Use lib/ui/kit/ instead:\n${bad.join('\n')}');
  });

  test('allow-list only holds files that still need migrating', () {
    final stale = [
      for (final f in _legacyAllowList)
        if (!File(f).existsSync() || violations(f).isEmpty) f,
    ];
    expect(stale, isEmpty, reason: 'Remove these from _legacyAllowList: $stale');
  });

  test('the guard actually detects violations', () {
    expect(_forbidden.hasMatch('return Scaffold('), isTrue);
    expect(_forbidden.hasMatch('Icon(Icons.map)'), isTrue);
    expect(_forbidden.hasMatch('CupertinoButton('), isTrue);
    expect(_forbidden.hasMatch('BBCard('), isFalse);
    expect(_forbidden.hasMatch('final scaffoldKey = 1;'), isFalse);
  });
}

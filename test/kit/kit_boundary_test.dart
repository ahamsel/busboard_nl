import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Material/Cupertino widgets and Material theme reads that must not appear
/// in screen code.
final _forbidden = RegExp(
  r'\b(Scaffold|AppBar|NavigationBar|NavigationDestination|BottomNavigationBar|'
  r'FloatingActionButton|ListTile|Card|ElevatedButton|FilledButton|TextButton|'
  r'OutlinedButton|IconButton|SegmentedButton|Switch|SwitchListTile|Chip|FilterChip|'
  r'ChoiceChip|ActionChip|SnackBar|AlertDialog|showModalBottomSheet|showDialog|'
  r'RefreshIndicator|InkWell|Badge|Slider|Cupertino[A-Z]\w*|'
  r'Material|Ink|InkResponse|Dialog|SimpleDialog|Drawer|Divider|VerticalDivider|'
  r'CircularProgressIndicator|LinearProgressIndicator|Tooltip|TextField|'
  r'TextFormField|Checkbox|CheckboxListTile|Radio|RadioListTile|DropdownButton|'
  r'DropdownMenu|PopupMenuButton|ExpansionTile|NavigationRail|NavigationDrawer|'
  r'TabBar|TabBarView|Stepper|InputChip|RawChip|SearchBar|SearchAnchor|'
  r'MaterialPageRoute|showBottomSheet|showDatePicker|showTimePicker|'
  r'ScaffoldMessenger|SelectableText|SliverAppBar|BackButton|CloseButton|Scrollbar|'
  r'CircleAvatar|MenuAnchor|ToggleButtons|DataTable|ExpansionPanel|showLicensePage|'
  r'LicensePage|showSearch)\b\s*[.(<]'
  r'|\.showSnackBar\('
  r'|\bIcons\.'
  r'|\bTheme\.of\b|\bThemeData\b|\bColorScheme\b|\bColors\.',
);

/// Importing Material or Cupertino at all (screens use widgets.dart + kit.dart).
/// Catches anything the name list above misses, including `show`/`as` forms.
final _materialImport = RegExp(r'''^\s*(import|export)\s+['"]package:flutter/(material|cupertino)\.dart['"]''');

/// Screens not yet rebuilt on the kit. Covers Material/Cupertino widgets and
/// Material theme reads (Theme.of / ColorScheme / Colors), which Phase 2
/// replaces with context.bb. Phase 2 removes entries as it migrates each
/// file; the list must only ever shrink.
const _legacyAllowList = {
  'lib/ui/map/bus_bottom_sheet.dart',
  'lib/ui/map/map_screen.dart',
  'lib/ui/map/stop_bottom_sheet.dart',
  'lib/ui/settings/settings_screen.dart',
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

  bool importsMaterial(String path) => File(path).readAsLinesSync().any(_materialImport.hasMatch);

  test('screen code does not import Material or Cupertino', () {
    final bad = [
      for (final f in files)
        if (!_legacyAllowList.contains(f) && importsMaterial(f)) f,
    ];
    expect(
      bad,
      isEmpty,
      reason: 'Import package:flutter/widgets.dart and ui/kit/kit.dart instead:\n${bad.join('\n')}',
    );
  });

  test('the kit barrel does not re-export Material or Cupertino', () {
    final barrel = File('lib/ui/kit/kit.dart').readAsStringSync();
    expect(barrel.contains('flutter/material.dart'), isFalse);
    expect(barrel.contains('flutter/cupertino.dart'), isFalse);
  });

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

  test('the import guard detects Material and Cupertino imports', () {
    for (final bad in [
      "import 'package:flutter/material.dart';",
      'import "package:flutter/material.dart";',
      "import 'package:flutter/cupertino.dart' show CupertinoIcons;",
      "  import 'package:flutter/material.dart' hide Card;",
      "export 'package:flutter/material.dart';",
    ]) {
      expect(_materialImport.hasMatch(bad), isTrue, reason: bad);
    }
    for (final ok in [
      "import 'package:flutter/widgets.dart';",
      "import 'package:flutter/services.dart';",
      "import 'package:flutter/foundation.dart';",
      "import 'package:busboard_nl/ui/kit/kit.dart';",
      "// import 'package:flutter/material.dart';",
    ]) {
      expect(_materialImport.hasMatch(ok), isFalse, reason: ok);
    }
  });

  test('the guard actually detects violations', () {
    expect(_forbidden.hasMatch('return Scaffold('), isTrue);
    expect(_forbidden.hasMatch('Icon(Icons.map)'), isTrue);
    expect(_forbidden.hasMatch('CupertinoButton('), isTrue);
    expect(_forbidden.hasMatch('BBCard('), isFalse);
    expect(_forbidden.hasMatch('final scaffoldKey = 1;'), isFalse);
    for (final bad in [
      'Divider(',
      'TextField(',
      'CircularProgressIndicator.adaptive(',
      'Theme.of(context)',
      'Colors.white',
      'ScaffoldMessenger.of(context)',
      'x.showSnackBar(',
      'Material(',
      'SliverAppBar(',
      'BackButton(',
      'CloseButton(',
      'Scrollbar(',
      'CircleAvatar(',
      'MenuAnchor(',
      'ToggleButtons(',
      'DataTable(',
      'ExpansionPanel(',
      'showLicensePage(',
      'LicensePage(',
      'showSearch<String>(',
    ]) {
      expect(_forbidden.hasMatch(bad), isTrue, reason: bad);
    }
    for (final ok in [
      'BBTextField(',
      'BBSwitch(',
      'BBDivider(',
      'context.bb.colors.ink',
      'cardTheme: x',
      'final materialKey = 1;',
    ]) {
      expect(_forbidden.hasMatch(ok), isFalse, reason: ok);
    }
  });
}

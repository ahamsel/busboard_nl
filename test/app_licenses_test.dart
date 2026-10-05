import 'package:busboard_nl/app_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerAppLicenses adds the Figtree SIL Open Font License', () async {
    registerAppLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final figtree = entries.where((e) => e.packages.contains('Figtree')).toList();
    expect(figtree, isNotEmpty, reason: 'no license entry names Figtree');
    final text = figtree.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL Open Font License'));
  });

  test('registerAppLicenses adds the Phosphor Icons MIT License', () async {
    registerAppLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final phosphor = entries.where((e) => e.packages.contains('Phosphor Icons')).toList();
    expect(phosphor, isNotEmpty, reason: 'no license entry names Phosphor Icons');
    final text = phosphor.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('MIT License'));
  });
}

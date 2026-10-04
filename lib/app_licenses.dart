import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers licenses for bundled assets that Flutter's own license collection
/// doesn't see, so they appear in the in-app licence page. The OFL requires the
/// licence text to travel with the Figtree font files.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Figtree'], text);
  });
}

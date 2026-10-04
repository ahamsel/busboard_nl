import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers licenses for bundled assets that Flutter's own license collection
/// doesn't see, so they appear in the in-app licence page. The OFL requires the
/// licence text to travel with the Figtree font files; Phosphor's MIT licence
/// does the same for the vendored icon fonts.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Figtree'], text);
    final phosphor = await rootBundle.loadString('assets/fonts/phosphor/LICENSE.txt');
    yield LicenseEntryWithLineBreaks(['Phosphor Icons'], phosphor);
  });
}

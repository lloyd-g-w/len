import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/text/text_font.dart';

/// Adds the licences of the bundled text-box fonts (SIL Open Font License
/// 1.1, `assets/fonts/*-OFL.txt`) to the app's licence page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final font in TextFont.values) {
      final text = await rootBundle.loadString(font.licenseAsset);
      yield LicenseEntryWithLineBreaks(['${font.family} font'], text);
    }
  });
}

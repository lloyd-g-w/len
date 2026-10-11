import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_font.dart';

/// Runs before every test file: plugins without a platform side in tests
/// answer like an empty system clipboard, and the bundled text-box fonts
/// are loaded (tests otherwise only have the Ahem-like test font), so
/// text boxes measure and render as in the app.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('pasteboard'),
    (call) async => call.method == 'files' ? const <Object>[] : null,
  );
  await loadTextFonts();
  await testMain();
}

/// Loads every bundled text-box font family.
Future<void> loadTextFonts() async {
  for (final font in TextFont.values) {
    final loader = FontLoader(font.family);
    for (final (bold, italic) in [(false, false), (true, false), (false, true), (true, true)]) {
      if (italic && !font.hasItalic) continue;
      loader.addFont(rootBundle.load(font.asset(bold: bold, italic: italic)));
    }
    await loader.load();
  }
}

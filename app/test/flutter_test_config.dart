import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_font.dart';

/// Runs before every test file: plugins without a platform side in tests
/// and the platform channel answer like an empty system clipboard, and the bundled fonts
/// (Inter, the text-box fonts, Material Symbols) are loaded (tests otherwise only have the
/// Ahem-like test font), so the UI and text boxes measure and render as in the app.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('pasteboard'),
    (call) async => call.method == 'files' ? const <Object>[] : null,
  );
  mockEmptyClipboard();
  await loadTextFonts();
  await testMain();
}

/// Makes the system clipboard answer as empty (un-mocked platform calls
/// would never complete in widget tests). Tests that mock
/// [SystemChannels.platform] call this again when they are done.
void mockEmptyClipboard() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

/// Loads every bundled text-box font family, Inter's UI weights (500,
/// 600) and the Material Symbols Rounded icon font, so goldens show real
/// text and icons.
Future<void> loadTextFonts() async {
  for (final font in TextFont.values) {
    final loader = FontLoader(font.family);
    for (final (bold, italic) in [(false, false), (true, false), (false, true), (true, true)]) {
      if (italic && !font.hasItalic) continue;
      loader.addFont(rootBundle.load(font.asset(bold: bold, italic: italic)));
    }
    if (font == TextFont.inter) {
      loader
        ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
    }
    await loader.load();
  }
  final symbols = FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
    ..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'));
  await symbols.load();
}

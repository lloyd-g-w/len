import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_font.dart';
import 'package:len/features/documents/export/export_sheet.dart';
import 'package:len/features/editor/finger_reading.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/messages.dart';

/// Runs before every test file: plugins without a platform side in tests
/// and the platform channel answer like an empty system clipboard, and the bundled fonts
/// (Inter, the text-box fonts, Material Symbols) are loaded (tests otherwise only have the
/// Ahem-like test font), so the UI and text boxes measure and render as in the app. Each
/// test starts with no snack bar left from the one before and no export choices remembered.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('pasteboard'),
    (call) async => const {'files', 'peek'}.contains(call.method) ? const <Object>[] : null,
  );
  mockEmptyClipboard();
  // Each test starts with no snack bar behind it (the editor's tips keep a
  // minute away from one, app-wide).
  setUp(MessageQueue.debugReset);
  // Most tests draw with a finger on pages with content: no reading (R20-6)
  // unless a test turns it on.
  setUp(() => FingerReading.debugEnabled = false);
  // Each export sheet starts as on first use (R22-2 remembers the last).
  setUp(ExportMemory.reset);
  await loadTextFonts();
  await testMain();
}

/// Makes the system clipboard answer as empty (un-mocked platform calls
/// would never complete in widget tests). Tests that mock
/// [SystemChannels.platform] call this again when they are done.
void mockEmptyClipboard() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

/// Loads the UI font (Sofia Sans), every bundled text-box font family (and
/// their Arabic and Hebrew fallbacks) and
/// the Material Symbols Rounded icon font, so goldens show real text and
/// icons.
Future<void> loadTextFonts() async {
  for (final font in TextFont.bundled) {
    final loader = FontLoader(font.family);
    for (final (bold, italic) in [(false, false), (true, false), (false, true), (true, true)]) {
      if (italic && !font.hasItalic) continue;
      loader.addFont(rootBundle.load(font.asset(bold: bold, italic: italic)));
    }
    await loader.load();
  }
  for (final font in FallbackFont.values) {
    final loader = FontLoader(font.family)
      ..addFont(rootBundle.load(font.asset()))
      ..addFont(rootBundle.load(font.asset(bold: true)));
    await loader.load();
  }
  final ui = FontLoader(AppTheme.fontFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    ui.addFont(rootBundle.load('assets/fonts/SofiaSans-$weight.ttf'));
  }
  await ui.load();
  final symbols = FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
    ..addFont(
      rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'),
    );
  await symbols.load();
}

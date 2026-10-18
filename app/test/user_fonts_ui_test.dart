import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/domain/text/user_font.dart';
import 'package:len/features/documents/export/pdf_text.dart';
import 'package:len/features/editor/tools/text/font_menus.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/fonts/text_fonts.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/menus.dart';
import 'package:pdf/pdf.dart';

import 'support/font_fixtures.dart';

/// Caveat's file imported as a user font (loaded into the engine).
Future<UserFont> _caveatAsUserFont() async {
  final bytes = caveatFile();
  const sha = 'c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00';
  final font = UserFont(id: TextFont.userIdOf(sha), name: 'My hand', blob: sha, createdAt: 1);
  expect(await TextFonts.load(font.id, bytes), isTrue);
  TextFonts.setLibrary([font]);
  return font;
}

double _width(TextFont font) {
  final layout = TextLayout.layout(
    TextData(text: 'Handwriting quickly', font: font),
    double.infinity,
  );
  final w = layout.painter.width;
  layout.dispose();
  return w;
}

SurfaceElement _box(TextFont font, {bool bold = false}) => SurfaceElement(
  id: 'box',
  surfaceId: 'page',
  type: ElementType.text.name,
  rect: const Rect.fromLTWH(20, 20, 300, 60),
  rotation: 0,
  z: 1,
  createdAt: 1,
  data: TextData.rich(
    text: 'Handwriting',
    spans: [if (bold) const StyledRange(0, 4, SpanStyle(bold: true))],
    paras: const [],
    font: font,
  ).toJson(),
);

/// The PDF of [element] drawn by a [PdfTextWriter] reading user fonts with
/// [file]; null if the writer refused it (an image instead).
Future<String?> _pdf(SurfaceElement element, Uint8List? Function() file) async {
  final doc = PdfDocument();
  final page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
  final writer = PdfTextWriter(doc, userFont: (_) async => file());
  if (!await writer.draw(page.getGraphics(), element, pageHeight: 1000, k: 0.75)) return null;
  return String.fromCharCodes(await doc.save());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(TextFonts.reset);

  test('text in a loaded user font is laid out in it; a missing one in the default', () async {
    final missing = TextFont.user('0' * 32);
    expect(TextFonts.familyOf(missing), TextFont.inter.family);
    expect(_width(missing), _width(TextFont.inter));
    final font = await _caveatAsUserFont();
    expect(_width(font.font), closeTo(_width(TextFont.caveat), 0.01));
    expect(_width(font.font), isNot(closeTo(_width(TextFont.inter), 1)));
    // Removed: back to the default.
    TextFonts.setLibrary(const []);
    expect(_width(font.font), _width(TextFont.inter));
  });

  testWidgets('the font picker lists user fonts, names a missing one and picks', (tester) async {
    final font = await tester.runAsync(_caveatAsUserFont);
    TextFont? picked;
    Future<void> pump(TextFont current) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: FontMenuButton(font: current, onSelected: (f) => picked = f),
          ),
        ),
      ),
    );

    await pump(TextFont.inter);
    await tester.tap(find.byKey(const ValueKey('font-menu')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuRow<String>, 'Sans'), findsOneWidget);
    // No app: no import.
    expect(find.text('Import font…'), findsNothing);
    await tester.tap(find.widgetWithText(MenuRow<String>, 'My hand'));
    await tester.pumpAndSettle();
    expect(picked, font!.font);

    // A font this device doesn't have: named so, in grey, kept checked.
    final gone = TextFont.user('f' * 32);
    await pump(gone);
    expect(find.text('Missing font'), findsOneWidget);
    expect(find.byTooltip('Font: Missing font, shown in Sans'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('font-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Shown in Sans'), findsOneWidget);
    expect(find.widgetWithText(MenuRow<String>, 'My hand'), findsOneWidget);
  });

  group('PDF export', () {
    test('embeds a TrueType user font (subset) as the text\'s font', () async {
      final font = await _caveatAsUserFont();
      final pdf = await _pdf(_box(font.font, bold: true), caveatFile);
      expect(pdf, isNotNull);
      expect(pdf, contains('/FontFile2'));
      expect(pdf, contains('Caveat'));
      // Subset: its embedded file holds only the glyphs used.
      final lengths = [
        for (final m in RegExp(r'/Length1 (\d+)').allMatches(pdf!)) int.parse(m.group(1)!),
      ];
      expect(lengths.reduce((a, b) => a < b ? a : b), lessThan(caveatFile().length ~/ 4));
    });

    test('a missing user font is written in the default font', () async {
      final pdf = await _pdf(_box(TextFont.user('a' * 32)), () => null);
      expect(pdf, isNot(contains('Caveat')));
      expect(pdf, contains('Inter'));
    });

    test('a user font it cannot embed (no file, CFF) makes the box an image', () async {
      final font = await _caveatAsUserFont();
      expect(await _pdf(_box(font.font), () => null), isNull);
      final cff = sfnt(
        0x4F54544F,
        const ['cmap', 'head', 'hhea', 'hmtx', 'maxp', 'CFF '],
        {1: 'Some OTF'},
      );
      expect(await _pdf(_box(font.font), () => cff), isNull);
    });
  });
}

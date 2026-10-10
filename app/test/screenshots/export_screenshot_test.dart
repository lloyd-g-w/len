import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/export/export_options.dart';
import 'package:len/features/documents/export/export_sheet.dart';
import 'package:len/features/library/library_screen.dart';

import 'editor_screenshot_test.dart' show pumpEditor;
import 'screenshot_harness.dart';

/// The export sheet opened from the editor (share button, or "⋯" →
/// Export… on phones): a dialog on tablets, a bottom sheet on phones.
void main() {
  setUpAll(loadRealFonts);

  Future<void> openSheet(WidgetTester tester) async {
    final share = find.byTooltip('Export & share');
    if (share.evaluate().isNotEmpty) {
      await tester.tap(share);
    } else {
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.text('Export…'));
    }
    await settle(tester);
    expect(find.byType(ExportSheet), findsOneWidget);
  }

  for (final (name, size, dpr) in [
    ('tablet', const Size(1280, 800), 1.0),
    ('tablet_portrait', const Size(800, 1280), 1.0),
    ('phone', const Size(390, 844), 2.0),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('export sheet $name ${mode.name}', (tester) async {
        await pumpEditor(tester, size: size, dpr: dpr, mode: mode, phoneInsets: dpr > 1);
        await openSheet(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'export_${name}_${mode.name}');

        // A bad range shows its error inline; PNG adds the resolution.
        await tester.tap(find.text('PNG'));
        await tester.tap(find.text('Page range'));
        await settle(tester);
        await tester.enterText(find.byKey(const ValueKey('export-range')), '2-7');
        await settle(tester);
        expect(find.text('Pages are 1–3'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'export_${name}_${mode.name}_range');
      });
    }
  }

  testWidgets('export sheet with PDF backgrounds, narrow phone, large text', (tester) async {
    setWindow(tester, const Size(320, 640), dpr: 2);
    final services = seededServices();
    addTearDown(services.dispose);
    await pumpApp(tester, services, const LibraryScreen(), textScale: 1.3);
    final pages = [
      for (var i = 0; i < 12; i++)
        NotebookPage(
          id: 'p$i',
          notebookId: 'nb',
          sortKey: i.toDouble(),
          width: 794,
          height: 1123,
          paper: PaperStyle.lined,
          background: i.isEven ? PageBackground.pdf(blob: 'a' * 64, pageIndex: i) : null,
        ),
    ];
    unawaited(
      showExportSheet(
        tester.element(find.byType(LibraryScreen)),
        title: 'A rather long notebook title that has to be shortened',
        pages: pages,
        currentPage: 4,
        initialRange: ExportRange.current,
      ),
    );
    await settle(tester);
    expect(find.text('PDF backgrounds'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shoot(tester, 'export_narrow_large_text');
    await tester.scrollUntilVisible(
      find.text('PDF backgrounds'),
      100,
      scrollable: find
          .descendant(of: find.byType(ExportSheet), matching: find.byType(Scrollable))
          .first,
    );
    await settle(tester);
    await shoot(tester, 'export_narrow_large_text_scrolled');
  });
}

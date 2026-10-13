import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/pdf_glyphs.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/pdf/pdf_highlight_removal.dart';
import 'package:len/features/editor/pdf/pdf_highlights.dart';
import 'package:len/features/editor/pdf/pdf_interaction.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import 'pdf_interaction_test.dart' show openPdfEditor, pdfTextAt;
import 'pdf_test.dart' show pdfium;

/// "Remove highlight" in the PDF text menu: the highlights over the
/// selected text go, as one undo step.
void main() {
  group('which highlights cover a line', () {
    const page = NotebookPage(
      id: 'p',
      notebookId: 'n',
      sortKey: 1,
      width: 1000,
      height: 1000,
      paper: Paper(PaperStyle.blank),
    );
    // "Hello" from x 100 to 200, "world" from 220 to 320, 20 high at y 100;
    // the next line at y 130.
    const hello = PdfTextLine(0, 5, Rect.fromLTRB(0.1, 0.1, 0.2, 0.12), PdfTextDirection.ltr);
    const world = PdfTextLine(6, 11, Rect.fromLTRB(0.22, 0.1, 0.32, 0.12), PdfTextDirection.ltr);
    const next = PdfTextLine(12, 17, Rect.fromLTRB(0.1, 0.13, 0.32, 0.15), PdfTextDirection.ltr);

    Stroke clean(PdfTextLine line) => PdfHighlights.stroke(
      line,
      page,
      id: 'h',
      color: 0xFFFFEB3B,
      style: const StrokeStyle(),
      createdAt: 1,
    )!;

    Stroke freehand(List<Offset> points) => Stroke(
      id: 'f',
      surfaceId: 'p',
      tool: InkTool.highlighter,
      color: 0xFFFFEB3B,
      width: 22,
      points: [for (final p in points) StrokePoint(p.dx, p.dy, 0.5)],
      createdAt: 1,
    );

    bool covers(Stroke s, PdfTextLine line) =>
        PdfHighlightCover.covers(s, PdfHighlightCover.lineArea(line, page));

    test('a highlight covers its words, not the next word or line', () {
      expect(covers(clean(hello), hello), isTrue);
      expect(covers(clean(world), hello), isFalse, reason: 'the word beside it');
      expect(covers(clean(next), hello), isFalse, reason: 'the line below');
      expect(covers(clean(next), world), isFalse);
    });

    test('a freehand highlight across part of a word covers it', () {
      // Two points far apart, crossing the middle of "Hello" (no point inside).
      expect(covers(freehand([const Offset(150, 95), const Offset(190, 125)]), hello), isTrue);
      expect(covers(freehand([const Offset(50, 112), const Offset(90, 112)]), hello), isFalse);
    });
  });

  group('in the editor', () {
    late Directory dir;
    late AppServices services;

    setUpAll(() {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
    });
    setUp(() {
      dir = Directory.systemTemp.createTempSync('len_pdf_highlight_removal_');
      services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
    });
    tearDown(() {
      services.dispose();
      dir.deleteSync(recursive: true);
    });

    Iterable<Stroke> strokesOn(PdfInteraction pdf) {
      final page = pdf.doc.pages.first;
      return pdf.doc.surfaces.surfaceOf(page.id).model.strokesNear(Offset.zero & page.size);
    }

    testWidgets('select highlighted text, remove its highlight, undo', skip: pdfium == null, (
      tester,
    ) async {
      final pdf = await openPdfEditor(tester, services, dir);
      pdf.tools.stylusOnly = true; // Fingers navigate: a long press selects.
      final remove = find.byKey(const ValueKey('pdf-remove-highlight'));
      // Highlight "Hello PDF world" and "Second line of text".
      pdf.selectRange(
        pdf.textPointAt(pdfTextAt(pdf, 'Hello'))!,
        pdf.textPointAt(pdfTextAt(pdf, 'text', i: 3))!,
        menu: true,
      );
      await tester.pumpAndSettle();
      expect(remove, findsNothing, reason: 'nothing highlighted yet');
      await tester.tap(find.byKey(const ValueKey('pdf-highlight')));
      await tester.pumpAndSettle();
      expect(strokesOn(pdf), hasLength(2));

      // A word of the second line: only that line's highlight goes.
      await tester.longPressAt(pdfTextAt(pdf, 'line'), kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(pdf.selection.text, 'line');
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(pdf.selection.isEmpty, isTrue);
      final left = strokesOn(pdf).single;
      expect(left.bounds.center.dy, lessThan((842 - 740) * 4 / 3), reason: 'the first line');

      // One undo brings it back.
      pdf.doc.surfaces.undo();
      expect(strokesOn(pdf), hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the menu fits a phone with Remove highlight', skip: pdfium == null, (
      tester,
    ) async {
      final pdf = await openPdfEditor(tester, services, dir, size: const Size(360, 740));
      pdf.selectRange(
        pdf.textPointAt(pdfTextAt(pdf, 'Hello'))!,
        pdf.textPointAt(pdfTextAt(pdf, 'world', i: 4))!,
        menu: true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-highlight')));
      await tester.pumpAndSettle();
      expect(pdf.selectWordAt(pdfTextAt(pdf, 'PDF')), isTrue);
      await tester.pumpAndSettle();
      final remove = find.byKey(const ValueKey('pdf-remove-highlight'));
      expect(remove, findsOneWidget);
      expect(tester.takeException(), isNull); // No overflow.
      final screen = tester.getRect(find.byType(EditorScreen));
      for (final key in ['pdf-copy', 'pdf-select-all', 'pdf-remove-highlight']) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight), isTrue);
      }
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(strokesOn(pdf), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

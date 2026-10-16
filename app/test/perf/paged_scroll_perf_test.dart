@Tags(['perf'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/ui/app_theme.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import '../pdf_interaction_test.dart' show openPdfEditor;
import '../pdf_test.dart' show pdfium;
import '../support/zoom_fixtures.dart';
import 'support/big_library.dart';
import 'support/frame_counts.dart';

/// A frame of a paged notebook scrolling: widgets rebuilt and render
/// objects painted (the pages' painters and the layers over them), on
/// plain pages full of handwriting with text boxes and images, at the top
/// and at the end (the "Add page" footer in view), and on PDF pages.
///
/// Run: `tool/light.sh flutter test test/perf/paged_scroll_perf_test.dart`.
void main() {
  for (final end in [false, true]) {
    testWidgets(
      'plain pages with text boxes and images: scroll ${end ? 'at the end' : 'at the top'}',
      (tester) async {
        final services = await _pumpNotebook(tester);
        final doc = zoomSession(tester).doc!;
        if (end) {
          doc.viewport.panBy(const Offset(0, -100000));
          await tester.pumpAndSettle();
        }
        final run = await _scroll(tester, doc);
        report('PAGED ${end ? 'end' : 'top'} scroll: $run');
        await _close(tester);
        services.dispose();
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  group('PDF', () {
    late Directory dir;
    late AppServices services;
    setUpAll(() {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
    });
    setUp(() {
      dir = Directory.systemTemp.createTempSync('len_pdf_perf_');
      services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
    });
    tearDown(() {
      services.dispose();
      dir.deleteSync(recursive: true);
    });

    for (final selected in [false, true]) {
      testWidgets('PDF pages: scroll${selected ? ', text selected' : ''}', skip: pdfium == null, (
        tester,
      ) async {
        final pdf = await openPdfEditor(tester, services, dir, size: const Size(1000, 1300));
        if (selected) {
          final page = pdf.doc.pages.first;
          final glyphs = pdf.info.glyphs(page.background!.blob, 0)!;
          pdf.selection.select(page, glyphs, 0, glyphs.text.length, menu: true);
          await tester.pumpAndSettle();
        }
        final run = await _scroll(tester, pdf.doc);
        report('PAGED pdf${selected ? ' selected' : ''} scroll: $run');
        await _close(tester);
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}

/// 120 frames of a slow scroll back and forth.
Future<String> _scroll(WidgetTester tester, DocumentController doc) => countFrames((i) async {
  doc.viewport.panBy(Offset(0, i.isEven ? -6.1 : 5.3));
  await tester.pump(const Duration(milliseconds: 16));
}, 120);

/// A notebook of three ruled pages full of handwriting (≈ 1,900 strokes
/// each), with two text boxes and an image on each, in a tablet-sized
/// editor.
Future<AppServices> _pumpNotebook(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1000, 1300)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = BenchClock();
  final services = AppServices.create(AppDatabase.inMemory(), clock: clock);
  final nb = services.notebooks.create(
    title: 'Lectures',
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
    firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
  );
  for (var i = 0; i < 2; i++) {
    services.pages.addPage(
      nb.id,
      template: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
    );
  }
  final png = (await tester.runAsync(_png))!;
  final blob = (await tester.runAsync(() => services.blobs.putBytes(png, mime: 'image/png')))!;
  for (final (i, page) in services.pages.pagesOf(nb.id).indexed) {
    services.strokes.save(pageOfInk(page.id, clock, lines: 25, seed: i));
    services.elements.save([
      for (final (j, at) in [const Offset(80, 120), const Offset(320, 560)].indexed)
        SurfaceElement(
          id: 'text-$i-$j',
          surfaceId: page.id,
          type: ElementType.text.name,
          rect: Rect.fromLTWH(at.dx, at.dy, 300, 40),
          z: 1,
          createdAt: 1,
          data: TextData(text: 'Box $j on page ${i + 1}').toJson(),
        ),
      SurfaceElement(
        id: 'image-$i',
        surfaceId: page.id,
        type: ElementType.image.name,
        rect: const Rect.fromLTWH(360, 260, 240, 160),
        z: -1,
        createdAt: 1,
        data: ImageData(blob: blob, width: 240, height: 160).toJson(),
      ),
    ]);
  }
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

/// A 240 × 160 PNG of two colours.
Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawColor(const Color(0xFF6B8FB5), BlendMode.src)
    ..drawCircle(const Offset(120, 80), 50, Paint()..color = const Color(0xFFE8C468));
  final image = await recorder.endRecording().toImage(240, 160);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

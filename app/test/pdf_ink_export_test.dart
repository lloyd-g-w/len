import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium;
import 'shape_fill_export_test.dart' show contentStreams;
import 'support/canvas_fixtures.dart' show scribbles;

/// Ink in exported PDFs (UX_AUDIT R22-1): the outline's own curves, a
/// written page well under a megabyte, and it looks as on screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppServices services;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() => services = AppServices.create(AppDatabase.inMemory()));
  tearDown(() => services.dispose());

  /// A blank page densely written: 400 strokes of 30 points.
  ({String id, List<Stroke> strokes}) writtenPage() {
    final nb = services.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = services.pages.pagesOf(nb.id).single;
    final strokes = [
      for (final s in scribbles(400, const ui.Rect.fromLTWH(60, 80, 650, 950), points: 30))
        Stroke(
          id: s.id,
          surfaceId: page.id,
          tool: s.tool,
          color: s.color,
          width: s.width,
          points: s.points,
          createdAt: s.createdAt,
          style: s.style,
        ),
    ];
    services.strokes.save(strokes);
    return (id: page.id, strokes: strokes);
  }

  test('ink is written as curves, a dense page in a few hundred KB', () async {
    final page = writtenPage();
    final exporter = NotebookExporter(services);
    final pdf = await exporter.pdf([services.pages.get(page.id)!]);
    await exporter.dispose();
    // Was 3 MB when outlines were sampled every 0.75 units.
    expect(pdf.length, lessThan(900 * 1024));
    final content = contentStreams(pdf).join('\n');
    final curves = RegExp(r' c\s').allMatches(content).length;
    final lines = RegExp(r' l\s').allMatches(content).length;
    expect(curves, greaterThan(lines * 5));
    // Coordinates carry at most two decimals.
    expect(RegExp(r'\d\.\d{3,} [\d.]+ [\d.]+ [\d.]+ [\d.]+ [\d.]+ c').hasMatch(content), isFalse);
    // No line to where the path already is (an arc starting at the end of
    // the segment before it: round caps and joins).
    final idle = RegExp(r'(?<![\d.])([\d.]+ [\d.]+) [cl]\s+\1 l\s').allMatches(content).length;
    expect(idle, 0, reason: '$idle zero-length lines of $lines');
  });

  test(
    'exported ink looks like the app\'s rendering',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final written = writtenPage();
      final page = services.pages.get(written.id)!;
      final exporter = NotebookExporter(services);
      final pdf = await exporter.pdf([page]);
      final png = await exporter.png(page, scale: 1);
      await exporter.dispose();
      final doc = await PdfDocument.openData(pdf);
      final w = page.width.round(), h = page.height.round();
      final rendered = (await doc.pages.single.render(fullWidth: w * 1.0, fullHeight: h * 1.0))!;
      final a = await rendered.createImage();
      rendered.dispose();
      await doc.dispose();
      final b = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
      Future<Uint8List> rgba(ui.Image i) async =>
          (await i.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final pa = await rgba(a), pb = await rgba(b);
      var ink = 0, differ = 0;
      for (var i = 0; i < pa.length; i += 4) {
        final la = pa[i] + pa[i + 1] + pa[i + 2], lb = pb[i] + pb[i + 1] + pb[i + 2];
        if (la < 600 || lb < 600) ink++;
        if ((la - lb).abs() > 3 * 96) differ++;
      }
      expect(ink, greaterThan(20000));
      // Edges antialias differently; the shapes match.
      expect(differ / ink, lessThan(0.02));
    },
  );
}

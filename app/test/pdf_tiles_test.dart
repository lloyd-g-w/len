import 'dart:io';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/features/documents/pdf/pdf_background_cache.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/documents/pdf/pdf_tiles.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium, pixel;

const a4 = Size(794, 1123);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tiling geometry', () {
    test('levels are powers of two above the whole-page limit', () {
      expect(PdfTiling.levelFor(100), 4096);
      expect(PdfTiling.levelFor(4096), 4096);
      expect(PdfTiling.levelFor(4097), 8192);
      expect(PdfTiling.levelFor(1e9), PdfTiling.maxLevel);
    });

    test('tiles cover the page exactly; only visible ones are listed', () {
      const width = 4096;
      final rows = (PdfTiling.heightAt(width, a4) / PdfTiling.tileSize).ceil();
      final all = PdfTiling.range(a4, Offset.zero & a4, width)!;
      expect((all.col0, all.col1, all.row0, all.row1), (0, 7, 0, rows - 1));
      var area = 0.0;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < 8; c++) {
          final rect = PdfTiling.rectOf(a4, width, c, r);
          area += rect.width * rect.height;
        }
      }
      expect(area, closeTo(a4.width * a4.height, 1e-6));
      // 1 page unit ≈ 5.16 px: a 100-unit square near the middle spans 2×2 tiles.
      final some = PdfTiling.range(a4, const Rect.fromLTWH(380, 540, 100, 100), width)!;
      expect((some.col0, some.col1, some.row0, some.row1), (3, 4, 5, 6));
      expect(PdfTiling.range(a4, const Rect.fromLTWH(900, 0, 10, 10), width), isNull);
      final last = PdfTiling.pixels(a4, width, 7, rows - 1);
      expect(last.x + last.width, width);
      expect(last.y + last.height, PdfTiling.heightAt(width, a4));
    });
  });

  group('rendering', () {
    late Directory dir;
    late AppServices services;
    setUpAll(() {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
    });
    setUp(() {
      dir = Directory.systemTemp.createTempSync('len_pdf_tiles_');
      services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
    });
    tearDown(() {
      services.dispose();
      dir.deleteSync(recursive: true);
    });

    test(
      'deep zoom renders sharp tiles of the visible part only',
      skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
      () async {
        // An A4 page with a 0.3 pt black vertical line at x = 297.5 pt.
        final doc = pw.PdfDocument();
        final page = pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a4);
        page.getGraphics()
          ..setStrokeColor(pw.PdfColors.black)
          ..setLineWidth(0.3)
          ..moveTo(297.5, 0)
          ..lineTo(297.5, 842)
          ..strokePath();
        final file = File('${dir.path}/line.pdf')..writeAsBytesSync(await doc.save());
        final importer = PdfImporter(services);
        final sha = await importer.store(XFile(file.path));
        await importer.dispose();
        final background = PageBackground.pdf(blob: sha, pageIndex: 0);
        final pdfA4 = Size(
          pw.PdfPageFormat.a4.width * worldPerPoint,
          pw.PdfPageFormat.a4.height * worldPerPoint,
        );
        final cache = PdfBackgroundCache(blobs: services.blobs, fetch: (_) async => true);
        addTearDown(cache.dispose);

        // 20 device pixels per page unit (page ≈ 15880 px wide); a 20×20-unit
        // window around the line (x = 396.67 units) → 400×400 px.
        const ppu = 20.0;
        const visible = Rect.fromLTWH(386.67, 500, 20, 20);
        Future<ui.Image> frame() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..scale(ppu)
            ..translate(-visible.left, -visible.top);
          cache.paint(canvas, background, pdfA4, visible, ppu);
          return recorder.endRecording().toImage(400, 400);
        }

        for (var i = 0; i < 100 && cache.debugTileCount < 2; i++) {
          await frame();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final image = await frame();
        expect(cache.debugTileCount, lessThanOrEqualTo(2)); // Not the whole page.
        if (Platform.environment['LEN_DEBUG_EXPORT'] != null) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/len_tile.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
        // The line is 0.3 pt = 0.4 units = 8 px wide, centred at x = 200.
        expect((await pixel(image, 200, 200)).r, lessThan(0.2));
        // Sharp: 10 px beside it is paper (a 2048 px page image would smear it).
        expect((await pixel(image, 190, 200)).r, greaterThan(0.95));
        expect((await pixel(image, 210, 200)).r, greaterThan(0.95));
        // Two tiles meet inside the line (8192 px of 16384 = 396.86 units →
        // x = 203.7) without a lighter seam.
        expect(cache.debugTileCount, 2);
        for (final x in [201, 202, 203]) {
          expect((await pixel(image, x, 100)).r, lessThan(0.2));
        }
      },
    );
  });
}

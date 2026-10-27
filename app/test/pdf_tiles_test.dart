import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/features/documents/pdf/pdf_background_cache.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';
import 'package:len/features/documents/pdf/pdf_tiles.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium, pixel;

const a4 = Size(794, 1123);

/// Records the widths whole pages and tiles are rendered at.
class _SizeRecorder extends PdfRenderer {
  _SizeRecorder(super.blobs);

  final pages = <int>[];
  final tiles = <int>[];

  @override
  Future<ui.Image?> render(
    String sha,
    int index,
    int pixelWidth, {
    bool Function()? stillWanted,
  }) async {
    pages.add(pixelWidth);
    return _image();
  }

  @override
  Future<ui.Image?> renderArea(
    String sha,
    int index, {
    required int fullWidth,
    required int fullHeight,
    required int x,
    required int y,
    required int width,
    required int height,
    bool Function()? stillWanted,
  }) async {
    tiles.add(fullWidth);
    return _image();
  }

  static Future<ui.Image> _image() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    return recorder.endRecording().toImage(1, 1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tiling geometry', () {
    test('levels are powers of two above the whole-page limit', () {
      expect(PdfTiling.levelFor(100), 4096);
      expect(PdfTiling.levelFor(4096), 4096);
      expect(PdfTiling.levelFor(4097), 8192);
      expect(PdfTiling.levelFor(1e9), PdfTiling.maxLevel);
      expect(PdfTiling.levelFor(100, above: 150), 256);
      expect(PdfTiling.levelFor(300, above: 150), 512);
    });

    test('a whole page is never taller than the limit', () {
      expect(PdfTiling.wholePageWidth(a4), PdfTiling.wholePageMax);
      expect(PdfTiling.wholePageWidth(const Size(1000, 20000)), PdfTiling.wholePageTall ~/ 20);
      expect(PdfTiling.wholePageWidth(const Size(1, 1e9)), 1);
    });

    test('tiles cover the page exactly; only visible ones are listed', () {
      const width = 4096;
      final cols = width ~/ PdfTiling.tileSize;
      final rows = (PdfTiling.heightAt(width, a4) / PdfTiling.tileSize).ceil();
      final all = PdfTiling.range(a4, Offset.zero & a4, width)!;
      expect((all.col0, all.col1, all.row0, all.row1), (0, cols - 1, 0, rows - 1));
      var area = 0.0;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final rect = PdfTiling.rectOf(a4, width, c, r);
          area += rect.width * rect.height;
        }
      }
      expect(area, closeTo(a4.width * a4.height, 1e-6));
      // 1 page unit ≈ 5.16 px: a 100-unit square near the middle (pixels
      // 1960–2476 across, 2786–3302 down) spans 2×2 tiles of 1024 px.
      expect(PdfTiling.tileSize, 1024);
      final some = PdfTiling.range(a4, const Rect.fromLTWH(380, 540, 100, 100), width)!;
      expect((some.col0, some.col1, some.row0, some.row1), (1, 2, 2, 3));
      expect(PdfTiling.range(a4, const Rect.fromLTWH(900, 0, 10, 10), width), isNull);
      final last = PdfTiling.pixels(a4, width, cols - 1, rows - 1);
      expect(last.x + last.width, width);
      expect(last.y + last.height, PdfTiling.heightAt(width, a4));
    });
  });

  test('a very tall page is rendered whole at most the limit tall, tiles beyond', () async {
    final dir = Directory.systemTemp.createTempSync('len_pdf_tall_');
    final services = AppServices.create(
      AppDatabase.inMemory(),
      blobBackend: FileBlobBackend(dir.path),
    );
    addTearDown(() {
      services.dispose();
      dir.deleteSync(recursive: true);
    });
    final sha = await services.blobs.putBytes(Uint8List(8), mime: 'application/pdf');
    final renderer = _SizeRecorder(services.blobs);
    final cache = PdfBackgroundCache(
      blobs: services.blobs,
      fetch: (_) async => true,
      renderer: renderer,
    );
    addTearDown(cache.dispose);
    final background = PageBackground.pdf(blob: sha, pageIndex: 0);
    const tall = Size(800, 16000); // A long receipt or web page.
    Future<void> paint(double ppu, Rect visible) async {
      final recorder = ui.PictureRecorder();
      cache.paint(Canvas(recorder), background, tall, visible, ppu);
      recorder.endRecording().dispose();
      while (cache.isBusy) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // 1600 px wide (32000 px tall whole), the top 1600 × 1200 px in view.
    await paint(2, const Rect.fromLTWH(0, 0, 800, 600));
    expect(renderer.pages, isNotEmpty);
    for (final width in renderer.pages) {
      expect(PdfTiling.heightAt(width, tall), lessThanOrEqualTo(PdfTiling.wholePageTall));
    }
    // The part in view comes sharp from tiles, a few of them.
    expect(renderer.tiles, isNotEmpty);
    expect(renderer.tiles.length, lessThan(16));
    expect(renderer.tiles.every((w) => w >= 1600), isTrue);
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

        // Until the two tiles the view needs are rendered (real time: PDFium).
        final watch = Stopwatch()..start();
        while (cache.debugTileCount < 2 && watch.elapsed < const Duration(seconds: 60)) {
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

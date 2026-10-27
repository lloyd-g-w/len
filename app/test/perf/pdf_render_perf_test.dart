@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../pdf_test.dart' show pdfium;
import 'support/pdf_bench.dart';
import 'support/pdf_fixtures.dart';

/// PDFium itself, as Len drives it (`PdfRenderer` → pdfrx → PDFium on
/// pdfrx's worker isolate): opening documents, rendering whole pages at
/// the widths the cache asks for, the tiles of deep zoom, and the UI
/// isolate's share (`PdfImage.createImage`: the pixel copy and the
/// engine's image). Real documents from [PdfFixtures].
///
/// Run: `nix develop -c bash -c 'cd app && flutter test test/perf/pdf_render_perf_test.dart'`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
    await pdfrxFlutterInitialize();
  });

  test(
    'fixtures',
    () async {
      final w = Stopwatch()..start();
      for (final f in [
        await PdfFixtures.textbook(),
        await PdfFixtures.scanned(),
        await PdfFixtures.vector(),
      ]) {
        report(
          'PDF fixture ${f.path.split('/').last}: ${(f.lengthSync() / 1e6).toStringAsFixed(1)} MB',
        );
      }
      report('PDF fixtures ready in ${w.elapsedMilliseconds} ms');
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: pdfium == null,
  );

  test(
    'open: all pages measured (as Len opens) vs progressive',
    () async {
      for (final f in [
        await PdfFixtures.textbook(),
        await PdfFixtures.scanned(),
        await PdfFixtures.vector(),
      ]) {
        final name = f.path.split('/').last;
        final full = <int>[], progressive = <int>[], first = <int>[];
        for (var run = 0; run < 3; run++) {
          var w = Stopwatch()..start();
          final doc = await PdfDocument.openFile(f.path);
          full.add(w.elapsedMilliseconds);
          w = Stopwatch()..start();
          final p = doc.pages.first;
          final img = await p.render(fullWidth: 2048, fullHeight: 2048 * p.height / p.width);
          (await img!.createImage()).dispose();
          img.dispose();
          first.add(w.elapsedMilliseconds);
          await doc.dispose();
          w = Stopwatch()..start();
          final lazy = await PdfDocument.openFile(f.path, useProgressiveLoading: true);
          progressive.add(w.elapsedMilliseconds);
          await lazy.dispose();
        }
        report(
          'PDF open $name: all pages ${stats(full)}; progressive ${stats(progressive)}; '
          'then page 1 at 2048 px ${stats(first)}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: pdfium == null,
  );

  test(
    'whole-page renders by width: worker vs UI isolate',
    () async {
      final cases = [
        ('text', await PdfFixtures.textbook(), 1),
        ('text+figure', await PdfFixtures.textbook(), 2),
        ('scan 300dpi', await PdfFixtures.scanned(), 1),
        ('vector map', await PdfFixtures.vector(), 1),
      ];
      for (final (name, file, index) in cases) {
        final doc = await PdfDocument.openFile(file.path);
        final page = doc.pages[index];
        for (final width in [256, 362, 1024, 1448, 2048]) {
          final worker = <int>[], create = <int>[], syncCopy = <int>[];
          for (var run = 0; run < 3; run++) {
            final height = (width * page.height / page.width).roundToDouble();
            var w = Stopwatch()..start();
            final img = (await page.render(
              fullWidth: width.toDouble(),
              fullHeight: height,
              backgroundColor: 0xFFFFFFFF,
            ))!;
            worker.add(w.elapsedMilliseconds);
            w = Stopwatch()..start();
            final f = ui.ImmutableBuffer.fromUint8List(img.pixels);
            syncCopy.add(w.elapsedMicroseconds);
            (await f).dispose();
            w = Stopwatch()..start();
            (await img.createImage()).dispose();
            create.add(w.elapsedMilliseconds);
            img.dispose();
          }
          report(
            'PDF render $name @${width}px: worker best ${worker.reduce(math.min)} ms '
            '(${stats(worker)}); createImage best ${create.reduce(math.min)} ms; '
            'sync pixel copy on UI isolate best ${syncCopy.reduce(math.min)} µs',
          );
        }
        await doc.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: pdfium == null,
  );

  test(
    'deep zoom tiles: a tablet screen of 512-px tiles vs one whole page',
    () async {
      // Android tablet portrait: 1600 × 2560 px, the page fit to width at 1×.
      const screen = ui.Size(1600, 2560);
      final cases = [
        ('text', await PdfFixtures.textbook(), 1),
        ('scan 300dpi', await PdfFixtures.scanned(), 1),
        ('vector map', await PdfFixtures.vector(), 1),
      ];
      for (final (name, file, index) in cases) {
        final doc = await PdfDocument.openFile(file.path);
        final page = doc.pages[index];
        for (final zoom in [2, 4, 8]) {
          final level = _pow2Above(screen.width * zoom);
          final fullH = (level * page.height / page.width).round();
          // The screen centred on the page.
          final x0 = ((level - screen.width) / 2).floor(),
              y0 = ((fullH - screen.height) / 2).floor();
          final tiles = <(int, int)>[
            for (var r = y0 ~/ 512; r <= (y0 + screen.height - 1) ~/ 512; r++)
              for (var c = x0 ~/ 512; c <= (x0 + screen.width - 1) ~/ 512; c++) (c, r),
          ];
          final per = <int>[];
          final all = Stopwatch()..start();
          for (final (c, r) in tiles) {
            final w = Stopwatch()..start();
            final img = await page.render(
              x: c * 512,
              y: r * 512,
              width: math.min(512, level - c * 512),
              height: math.min(512, fullH - r * 512),
              fullWidth: level.toDouble(),
              fullHeight: fullH.toDouble(),
              backgroundColor: 0xFFFFFFFF,
            );
            (await img!.createImage()).dispose();
            img.dispose();
            per.add(w.elapsedMilliseconds);
          }
          final screenMs = all.elapsedMilliseconds;
          // The same screen as one area render (one page load, one pass).
          final w = Stopwatch()..start();
          final one = await page.render(
            x: x0,
            y: y0,
            width: screen.width.toInt(),
            height: screen.height.toInt(),
            fullWidth: level.toDouble(),
            fullHeight: fullH.toDouble(),
            backgroundColor: 0xFFFFFFFF,
          );
          (await one!.createImage()).dispose();
          one.dispose();
          report(
            'PDF tiles $name zoom $zoom× (level $level px): ${tiles.length} tiles in '
            '$screenMs ms, a tile ${stats(per)}; the same screen as one render '
            '${w.elapsedMilliseconds} ms',
          );
        }
        await doc.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: pdfium == null,
  );

  test(
    'tile size: a tablet screen at 4× in 512, 1024 and 2048-px tiles',
    () async {
      const screen = ui.Size(1600, 2560);
      for (final (name, file) in [
        ('text', await PdfFixtures.textbook()),
        ('scan 300dpi', await PdfFixtures.scanned()),
        ('vector map', await PdfFixtures.vector()),
      ]) {
        final doc = await PdfDocument.openFile(file.path);
        final page = doc.pages[1];
        final level = _pow2Above(screen.width * 4);
        final fullH = (level * page.height / page.width).round();
        final x0 = ((level - screen.width) / 2).floor(), y0 = ((fullH - screen.height) / 2).floor();
        final out = <String>[];
        for (final size in [512, 1024, 2048]) {
          var n = 0;
          final w = Stopwatch()..start();
          for (var r = y0 ~/ size; r <= (y0 + screen.height - 1) ~/ size; r++) {
            for (var c = x0 ~/ size; c <= (x0 + screen.width - 1) ~/ size; c++) {
              final img = await page.render(
                x: c * size,
                y: r * size,
                width: math.min(size, level - c * size),
                height: math.min(size, fullH - r * size),
                fullWidth: level.toDouble(),
                fullHeight: fullH.toDouble(),
                backgroundColor: 0xFFFFFFFF,
              );
              (await img!.createImage()).dispose();
              img.dispose();
              n++;
            }
          }
          out.add('$size px: $n tiles ${w.elapsedMilliseconds} ms');
        }
        report('PDF tile size $name 4×: ${out.join('; ')}');
        await doc.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: pdfium == null,
  );

  test(
    'page text and links (the editor preloads them for pages in view)',
    () async {
      final doc = await PdfDocument.openFile((await PdfFixtures.textbook()).path);
      final text = <int>[], links = <int>[];
      for (var i = 0; i < 10; i++) {
        var w = Stopwatch()..start();
        await doc.pages[i].loadText();
        text.add(w.elapsedMilliseconds);
        w = Stopwatch()..start();
        await doc.pages[i].loadLinks();
        links.add(w.elapsedMilliseconds);
      }
      report('PDF page text (loadText) ${stats(text)}; links (loadLinks) ${stats(links)}');
      await doc.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: pdfium == null,
  );
}

int _pow2Above(double v) {
  var l = 1;
  while (l < v) {
    l *= 2;
  }
  return l;
}

// ignore: avoid_print
void report(String line) => print(line);

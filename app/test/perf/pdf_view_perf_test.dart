@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/pdf_text_source.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/features/documents/pdf/pdf_background_cache.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/documents/pdf/pdf_tiles.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart';

import '../pdf_test.dart' show pdfium;
import 'support/pdf_bench.dart';
import 'support/pdf_fixtures.dart';

/// PDF viewing as the editor drives it: [PdfBackgroundCache] (the app's
/// cache, queue, buckets, tiles and eviction, unchanged) over a
/// [CountingRenderer] (the app's `PdfRenderer` with every render
/// recorded), real PDFium, the realistic documents of [PdfFixtures], and
/// frames painted in real time the way `DocumentPaperPainter` paints
/// them (60 Hz: paint, then wait for the next vsync).
///
/// What it cannot see: GPU upload/raster (flutter_test's engine records
/// pictures but rasterises nothing on a GPU) and the S Pen hardware. The
/// UI-isolate cost it reports is the Dart side: `paint` plus the turns
/// the render pipeline takes (`createImage`'s copy, the queue).
///
/// Run: `nix develop -c bash -c 'cd app && flutter test test/perf/pdf_view_perf_test.dart'`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppServices services;
  final shas = <String, String>{};

  setUpAll(() async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
    if (pdfium == null) return;
    dir = Directory.systemTemp.createTempSync('len_pdf_view_perf_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
    final importer = PdfImporter(services);
    for (final (name, file) in [
      ('textbook', await PdfFixtures.textbook()),
      ('scanned', await PdfFixtures.scanned()),
      ('vector', await PdfFixtures.vector()),
    ]) {
      final w = Stopwatch()..start();
      final sha = await importer.store(XFile(file.path));
      final store = w.elapsedMilliseconds;
      final specs = await importer.specsFor(sha);
      report(
        'PDF import $name (${specs.length} pages, ${(file.lengthSync() / 1e6).toStringAsFixed(1)} MB): '
        'store (hash + copy) $store ms, measure pages ${w.elapsedMilliseconds - store} ms',
      );
      shas[name] = sha;
    }
    await importer.dispose();
  });

  tearDownAll(() {
    if (pdfium == null) return;
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  // An A4 page in world units (as PdfImporter sizes it).
  const a4 = ui.Size(595.28 * worldPerPoint, 841.89 * worldPerPoint);
  const a3l = ui.Size(1190.55 * worldPerPoint, 841.89 * worldPerPoint);

  ({PdfBackgroundCache cache, CountingRenderer renderer}) newCache({bool dedupe = false}) {
    final renderer = CountingRenderer(services.blobs, skipLiveDuplicates: dedupe);
    final cache = PdfBackgroundCache(
      blobs: services.blobs,
      fetch: (_) async => true,
      renderer: renderer,
    );
    return (cache: cache, renderer: renderer);
  }

  List<PageBackground> backgroundsOf(String name, int count) => [
    for (var i = 0; i < count; i++) PageBackground.pdf(blob: shas[name]!, pageIndex: i),
  ];

  Future<void> vsync() => Future<void>.delayed(const Duration(milliseconds: 16));

  // Screens: an Android tablet in portrait (1600 × 2560 px, the page fit
  // to width) and a desktop window (1000 × 1300 px of canvas).
  const screens = {'tablet': ui.Size(1600, 2560), 'desktop': ui.Size(1000, 1300)};

  group('open', () {
    for (final name in ['textbook', 'scanned', 'vector']) {
      for (final MapEntry(key: screenName, value: screen) in screens.entries) {
        test(
          '$name on $screenName: first frame → first page sharp',
          () async {
            final page = name == 'vector' ? a3l : a4;
            final count = name == 'textbook' ? 300 : (name == 'scanned' ? 50 : 4);
            final stack = PageStack(count, page);
            final bgs = backgroundsOf(name, count);
            final (:cache, :renderer) = newCache();
            final ppu = screen.width / page.width;
            final world = ui.Offset.zero & (screen / ppu);
            // As the editor paints: a frame now, then one whenever the
            // cache notifies (a render landed); the view does not move.
            var dirty = true;
            cache.addListener(() => dirty = true);
            final w = Stopwatch()..start();
            int? firstPixels, sharp;
            var frames = 0;
            while (sharp == null && w.elapsed.inSeconds < 30) {
              if (dirty) {
                dirty = false;
                paintFrame(cache, stack, bgs, world, ppu);
                frames++;
              }
              final shown = shownOf(renderer, 0, page.width * ppu);
              if (shown != Shown.blank) firstPixels ??= w.elapsedMilliseconds;
              if (shown == Shown.sharp) sharp = w.elapsedMilliseconds;
              await vsync();
            }
            await _settle(cache);
            final asked = renderer.records.map((r) => 'p${r.page}@${r.width}').join(' ');
            final first = renderer.records.first;
            report(
              'PDF open $name/$screenName: page 1 sharp $sharp ms (first pixels $firstPixels ms, '
              '$frames frames); PDFium open (measures page 1 only) ${renderer.firstOpenUs! ~/ 1000} ms, '
              'page 1 render ${first.serviceUs ~/ 1000} ms incl. open; renders: $asked',
            );
            await _settle(cache);
            cache.dispose();
          },
          timeout: const Timeout(Duration(minutes: 2)),
          skip: pdfium == null,
        );
      }
    }
  });

  test(
    'textbook: right after import, page 1 while the search indexer reads its text',
    () async {
      // PdfImporter.createNotebook starts `search.indexPdfs()`: the indexer
      // reads the whole blob, opens a second PdfDocument and extracts every
      // page's text on the same PDFium worker as the page renders.
      const screen = ui.Size(1600, 2560);
      final stack = PageStack(300, a4);
      final bgs = backgroundsOf('textbook', 300);
      final (:cache, :renderer) = newCache();
      final ppu = screen.width / a4.width;
      final world = ui.Offset.zero & (screen / ppu);
      final clock = Stopwatch()..start();
      var indexed = 0;
      int? indexDone;
      final indexing = () async {
        final bytes = await services.blobs.read(shas['textbook']!);
        final doc = await const PdfrxTextSource().open(bytes!);
        for (var i = 0; i < doc.pageCount; i++) {
          await doc.pageText(i);
          indexed++;
        }
        await doc.dispose();
        indexDone = clock.elapsedMilliseconds;
      }();
      var dirty = true;
      cache.addListener(() => dirty = true);
      int? sharp;
      while (sharp == null && clock.elapsed.inSeconds < 30) {
        if (dirty) {
          dirty = false;
          paintFrame(cache, stack, bgs, world, ppu);
        }
        if (shownOf(renderer, 0, a4.width * ppu) == Shown.sharp) sharp = clock.elapsedMilliseconds;
        await vsync();
      }
      final pagesBefore = indexed;
      await indexing;
      report(
        'PDF open textbook/tablet while indexing: page 1 sharp $sharp ms (the indexer had read '
        '$pagesBefore pages by then; all 300 in $indexDone ms)',
      );
      await _settle(cache);
      cache.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: pdfium == null,
  );

  group('scroll', () {
    // The app as it is (one render per key in flight, a page prefetched
    // each side), then what-ifs simulated from outside the cache: no
    // prefetch, and low-res first (a 256-px image asked for each page in
    // view before the sharp one).
    for (final (name, count, pagesPerSecond, prefetch, lowRes) in [
      ('textbook', 100, 1.0, true, false),
      ('textbook', 100, 3.0, true, false),
      ('textbook', 100, 10.0, true, false),
      ('textbook', 100, 10.0, false, false),
      ('scanned', 50, 1.0, true, false),
      ('scanned', 50, 3.0, true, false),
      ('scanned', 50, 3.0, false, false),
      ('scanned', 50, 3.0, true, true),
    ]) {
      final variant = [if (!prefetch) 'no prefetch', if (lowRes) 'low-res first'].join(' + ');
      final label = variant.isEmpty ? 'as is' : 'what-if $variant';
      test(
        '$name: $count pages at $pagesPerSecond pages/s on a tablet ($label)',
        () async {
          const screen = ui.Size(1600, 2560);
          final stack = PageStack(count + 2, a4);
          final bgs = backgroundsOf(name, count + 2);
          final (:cache, :renderer) = newCache();
          final ppu = screen.width / a4.width;
          final viewH = screen.height / ppu;
          final pitch = a4.height + stack.gap;
          final rss = RssPeak();
          final probe = TurnProbe();
          final paintUs = <int>[];
          var sharp = 0, soft = 0, blank = 0, frames = 0, maxBytes = 0, maxImages = 0;
          final firstSharpAfterEnter = <int, int>{}, entered = <int, int>{};
          final clock = Stopwatch()..start();
          while (true) {
            final top = clock.elapsedMilliseconds / 1000 * pagesPerSecond * pitch;
            if (top > count * pitch) break;
            final world = ui.Rect.fromLTWH(0, top, a4.width, viewH);
            final p = Stopwatch()..start();
            paintFrame(cache, stack, bgs, world, ppu, prefetch: prefetch);
            if (lowRes) {
              for (final i in stack.visible(world)) {
                cache.imageFor(bgs[i], 256);
              }
            }
            paintUs.add(p.elapsedMicroseconds);
            frames++;
            for (final i in stack.visible(world)) {
              entered.putIfAbsent(i, () => clock.elapsedMilliseconds);
              switch (shownOf(renderer, i, a4.width * ppu)) {
                case Shown.sharp:
                  sharp++;
                  firstSharpAfterEnter.putIfAbsent(
                    i,
                    () => clock.elapsedMilliseconds - entered[i]!,
                  );
                case Shown.fallback:
                  soft++;
                case Shown.blank:
                  blank++;
              }
            }
            maxBytes = math.max(maxBytes, renderer.liveBytes);
            maxImages = math.max(
              maxImages,
              renderer.records.where((r) => r.image != null && !r.image!.debugDisposed).length,
            );
            await vsync();
          }
          final elapsed = clock.elapsedMilliseconds;
          probe.stop();
          rss.stop();
          final done = renderer.records.where((r) => !r.skipped).toList();
          // A render is wasted when its page left the screen before it was done.
          var wasted = 0;
          for (final r in done) {
            final t = r.done / 1000; // ms on the renderer clock ≈ scroll clock.
            final top = t / 1000 * pagesPerSecond * pitch;
            final world = ui.Rect.fromLTWH(0, top, a4.width, viewH);
            if (!stack.visible(world).contains(r.page)) wasted++;
          }
          final service = [for (final r in done) r.serviceUs ~/ 1000];
          final cells = sharp + soft + blank;
          String pct(int n) => '${(100 * n / cells).toStringAsFixed(0)}%';
          report(
            'PDF scroll $name ${pagesPerSecond}p/s ($label): $frames frames in $elapsed ms '
            '(expected ${(elapsed / 16.7).round()}); page-frames sharp ${pct(sharp)}, '
            'soft (lower-res fallback) ${pct(soft)}, blank ${pct(blank)}; '
            'entered→sharp ${stats(firstSharpAfterEnter.values.toList())}; '
            'renders ${done.length} (asked ${renderer.records.length}), duplicates ${renderer.duplicates}, '
            'done while off screen $wasted (wasted, unless prefetched); render service ${stats(service)}; '
            'widths ${{for (final r in done) r.width}}; '
            'paint ${stats([for (final u in paintUs) u / 1000])}; '
            'UI turns >16 ms ${probe.over(16)}, longest ${probe.longest} ms; '
            'live images peak ${maxBytes >> 20} MB in $maxImages (budget ${cache.budgetBytes >> 20} MB), '
            'orphaned at the end ${renderer.orphans.count} (${renderer.orphans.bytes >> 20} MB); '
            'RSS peak +${rss.deltaMb} MB',
          );
          await _settle(cache);
          cache.dispose();
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: pdfium == null,
      );
    }
  });

  group('zoom', () {
    for (final (name, page, size) in [
      ('textbook', 2, a4),
      ('scanned', 2, a4),
      ('vector', 1, a3l),
    ]) {
      for (final target in [2.0, 4.0]) {
        test(
          '$name: pinch 1× → $target× over 600 ms on a tablet, then hold',
          () async {
            const screen = ui.Size(1600, 2560);
            final stack = PageStack(page + 2, size);
            final bgs = backgroundsOf(name, page + 2);
            final (:cache, :renderer) = newCache();
            final fit = screen.width / size.width;
            final centre = stack.frameOf(page).center;
            // Warm: the page sharp at 1×.
            ui.Rect worldAt(double zoom) => ui.Rect.fromCenter(
              center: centre,
              width: screen.width / (fit * zoom),
              height: screen.height / (fit * zoom),
            );
            final warm = Stopwatch()..start();
            while (shownOf(renderer, page, size.width * fit) != Shown.sharp &&
                warm.elapsed.inSeconds < 20) {
              paintFrame(cache, stack, bgs, worldAt(1), fit);
              await vsync();
            }
            await _settle(cache);
            final before = renderer.records.length;
            final clock = Stopwatch()..start();
            final paintUs = <int>[];
            var zoom = 1.0;
            int? settledAt;
            final probe = TurnProbe();
            while (clock.elapsed.inSeconds < 20) {
              final t = clock.elapsedMilliseconds / 600;
              zoom = t >= 1 ? target : 1 + (target - 1) * t;
              final p = Stopwatch()..start();
              paintFrame(cache, stack, bgs, worldAt(zoom), fit * zoom);
              paintUs.add(p.elapsedMicroseconds);
              if (t >= 1 && !cache.isBusy) {
                settledAt = clock.elapsedMilliseconds;
                break;
              }
              await vsync();
            }
            probe.stop();
            final recs = renderer.records.sublist(before).where((r) => !r.skipped).toList();
            final wholeLimit = PdfTiling.wholePageWidth(size);
            final pixelWidth = size.width * fit * target;
            final finalLevel = pixelWidth <= wholeLimit
                ? PdfBackgroundCache.bucketFor(pixelWidth, max: wholeLimit)
                : PdfTiling.levelFor(pixelWidth, above: wholeLimit);
            final tiles = recs.where((r) => r.tile != null).toList();
            final finalTiles = tiles.where((r) => r.width == finalLevel).length;
            final frame = stack.frameOf(page);
            final range = PdfTiling.range(size, worldAt(target).shift(-frame.topLeft), finalLevel);
            final inFinalView = range == null
                ? 0
                : tiles.where((r) {
                    final (c, row) = r.tile!;
                    return r.width == finalLevel &&
                        c >= range.col0 &&
                        c <= range.col1 &&
                        row >= range.row0 &&
                        row <= range.row1;
                  }).length;
            final service = [for (final r in recs) r.serviceUs ~/ 1000];
            report(
              'PDF zoom $name 1×→$target×: sharp again ${settledAt == null ? '>20000' : settledAt - 600} ms '
              'after the pinch ended; renders ${recs.length} '
              '(${recs.length - tiles.length} whole pages at ${{for (final r in recs.where((r) => r.tile == null)) r.width}}, '
              '${tiles.length} tiles at ${{for (final r in tiles) r.width}}; $finalTiles at the final level $finalLevel, '
              '${tiles.length - finalTiles} for levels passed through, $inFinalView in the final view, '
              'duplicates ${renderer.duplicates}); render service ${stats(service)}; '
              'paint ${stats([for (final u in paintUs) u / 1000])}; UI turns >16 ms ${probe.over(16)}, '
              'longest ${probe.longest} ms; cache ${renderer.liveBytes >> 20} MB',
            );
            await _settle(cache);
            cache.dispose();
          },
          timeout: const Timeout(Duration(minutes: 2)),
          skip: pdfium == null,
        );
      }
    }

    test(
      'textbook: small zoom steps (desktop, ctrl+wheel 1.0 → 1.5 in 10% steps)',
      () async {
        const screen = ui.Size(1000, 1300);
        final stack = PageStack(3, a4);
        final bgs = backgroundsOf('textbook', 3);
        final (:cache, :renderer) = newCache();
        final fit = screen.width / a4.width;
        final centre = stack.frameOf(1).center;
        final zooms = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5];
        final clock = Stopwatch()..start();
        for (final z in zooms) {
          final world = ui.Rect.fromCenter(
            center: centre,
            width: screen.width / (fit * z),
            height: screen.height / (fit * z),
          );
          for (var f = 0; f < 15; f++) {
            paintFrame(cache, stack, bgs, world, fit * z);
            await vsync();
          }
        }
        await _settle(cache);
        final done = renderer.records.where((r) => !r.skipped).toList();
        report(
          'PDF zoom steps textbook 1.0→1.5 (desktop): ${done.length} renders of page 2 at '
          '${[for (final r in done.where((r) => r.page == 1)) r.width]} in ${clock.elapsedMilliseconds} ms',
        );
        cache.dispose();
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: pdfium == null,
    );
  });

  group('thumbnails', () {
    for (final (name, count) in [('textbook', 300), ('scanned', 50)]) {
      test(
        '$name: page overview grid, then the sidebar beside a sharp page',
        () async {
          // The overview grid: 24 tiles in view, ~180 dp wide at dpr 2 → 362 px.
          final (:cache, :renderer) = newCache();
          final bgs = backgroundsOf(name, count);
          final clock = Stopwatch()..start();
          final probe = TurnProbe();
          int? allShown;
          while (clock.elapsed.inSeconds < 60) {
            var shown = 0;
            for (var i = 0; i < 24; i++) {
              if (cache.imageFor(bgs[i], 360) != null) shown++;
            }
            if (shown == 24) {
              allShown = clock.elapsedMilliseconds;
              break;
            }
            await vsync();
          }
          probe.stop();
          final first24 = renderer.records.where((r) => !r.skipped).toList();
          // Scroll the grid through all pages: 24 more every 200 ms.
          final grid = Stopwatch()..start();
          for (var start = 24; start < count; start += 24) {
            final until = grid.elapsedMilliseconds + 200;
            while (grid.elapsedMilliseconds < until) {
              for (var i = start; i < math.min(count, start + 24); i++) {
                cache.imageFor(bgs[i], 360);
              }
              await vsync();
            }
          }
          await _settle(cache);
          final all = renderer.records.where((r) => !r.skipped).toList();
          final perThumb = [for (final r in all) r.serviceUs / 1000];
          report(
            'PDF overview $name: 24 thumbnails (362 px) in $allShown ms (${first24.length} renders); '
            'whole grid scrolled (${(count / 24).ceil()} screens, 200 ms each) → ${all.length} renders, '
            'a thumbnail ${stats(perThumb)}, ${renderer.liveBytes >> 20} MB cached; '
            'UI turns >16 ms ${probe.over(16)}',
          );
          cache.dispose();
        },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: pdfium == null,
      );
    }

    test(
      'scanned: sidebar thumbnails compete with the page on screen',
      () async {
        const screen = ui.Size(1600, 2560);
        final (:cache, :renderer) = newCache();
        final stack = PageStack(50, a4);
        final bgs = backgroundsOf('scanned', 50);
        final ppu = screen.width / a4.width;
        final world = ui.Rect.fromLTWH(0, stack.topOf(20), a4.width, screen.height / ppu);
        final clock = Stopwatch()..start();
        int? sharp;
        while (sharp == null && clock.elapsed.inSeconds < 30) {
          // The sidebar paints first (a dozen thumbnails, 120 dp at dpr 2)…
          for (var i = 14; i < 26; i++) {
            cache.imageFor(bgs[i], 240);
          }
          // …then the page.
          paintFrame(cache, stack, bgs, world, ppu);
          if (shownOf(renderer, 20, a4.width * ppu) == Shown.sharp)
            sharp = clock.elapsedMilliseconds;
          await vsync();
        }
        final order = renderer.records.where((r) => !r.skipped).map((r) => 'p${r.page}@${r.width}');
        report(
          'PDF sidebar+page scanned: page 21 sharp after $sharp ms; render order ${order.take(16).join(' ')}',
        );
        await _settle(cache);
        cache.dispose();
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: pdfium == null,
    );
  });
}

Future<void> _settle(PdfBackgroundCache cache) async {
  final w = Stopwatch()..start();
  while (cache.isBusy && w.elapsed.inSeconds < 30) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// ignore: avoid_print
void report(String line) => print(line);

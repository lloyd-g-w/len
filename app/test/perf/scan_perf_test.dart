import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/scan/quad_detector.dart';
import 'package:len/features/documents/scan/scan_job.dart';

import 'support/big_library.dart';

/// Document scan: the work behind a page, on a synthetic 12-MP photo
/// (a sheet of paper with lines of "ink", turned, on a dark desk). Natively
/// it all runs on worker isolates; on the web on the UI thread in bands
/// (`scan_runner_web.dart`), so the longest stretch between two yields is
/// what a frame waits for there.
///
/// Run: `tool/light.sh flutter test test/perf/scan_perf_test.dart`.
void main() {
  test('scan a 12-MP photo', () async {
    // The photo as the corner editor and the import decode it.
    final work = _photo(800, 600);
    final source = _photo(3200, 2400);
    final sheet = Quad(
      const Offset(0.18, 0.12),
      const Offset(0.84, 0.17),
      const Offset(0.80, 0.90),
      const Offset(0.14, 0.86),
    );
    Quad at(int w, int h) => Quad(
      sheet.topLeft.scale(w.toDouble(), h.toDouble()),
      sheet.topRight.scale(w.toDouble(), h.toDouble()),
      sheet.bottomRight.scale(w.toDouble(), h.toDouble()),
      sheet.bottomLeft.scale(w.toDouble(), h.toDouble()),
    );

    Quad? found;
    final detect = bestMs(() => found = QuadDetector.find(work));
    expect(found, isNotNull);

    final preview = ScanJob(
      source: work,
      quad: at(800, 600),
      filter: ScanFilter.colour,
      maxEdge: 320,
    );
    final previewMs = bestMs(preview.render);

    final full = ScanJob(source: source, quad: at(3200, 2400), filter: ScanFilter.colour);
    late RgbaImage page;
    final render = bestMs(() => page = full.render(), runs: 2);
    final encode = bestMs(() => full.encode(page), runs: 2);

    // As on the web: the longest stretch between two yields.
    var longest = 0;
    final slice = Stopwatch()..start();
    Future<void> yieldNow() async {
      longest = math.max(longest, slice.elapsedMilliseconds);
      await Future<void>.delayed(Duration.zero);
      slice.reset();
    }

    await full.runSliced(yieldNow);
    longest = math.max(longest, slice.elapsedMilliseconds);
    final sliced = longest;
    longest = 0;
    slice.reset();
    await full.renderSliced(yieldNow);
    report(
      'SCAN detect $detect ms (800 × 600); preview $previewMs ms (320 px); '
      'page ${page.width} × ${page.height}: render $render ms, JPEG $encode ms; '
      'web, longest UI stretch: rendering $longest ms, with encoding $sliced ms',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// A [width] × [height] photo: dark desk, a light sheet (as `sheet` in the
/// test, by fractions of the photo) with lines of dark marks.
RgbaImage _photo(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  final random = math.Random(3);
  for (var y = 0; y < height; y++) {
    // Whether each pixel of the row is on the sheet: its edges' crossings.
    final crossings = <double>[];
    final corners = [
      Offset(0.18 * width, 0.12 * height),
      Offset(0.84 * width, 0.17 * height),
      Offset(0.80 * width, 0.90 * height),
      Offset(0.14 * width, 0.86 * height),
    ];
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4];
      if ((a.dy <= y) != (b.dy <= y)) {
        crossings.add(a.dx + (y - a.dy) / (b.dy - a.dy) * (b.dx - a.dx));
      }
    }
    crossings.sort();
    final inked = (y ~/ (height / 40)).isEven && y % (height ~/ 40) < height / 160;
    for (var x = 0; x < width; x++) {
      final on = crossings.length == 2 && x >= crossings[0] && x <= crossings[1];
      final noise = random.nextInt(12);
      final v = on ? (inked && (x ~/ 7) % 3 != 0 ? 60 : 225) - noise : 50 + noise;
      final i = (y * width + x) * 4;
      pixels[i] = v;
      pixels[i + 1] = v;
      pixels[i + 2] = on ? v - 8 : v + 10;
      pixels[i + 3] = 255;
    }
  }
  return RgbaImage(pixels, width, height);
}

import 'dart:math' as math;

import '../../app_services.dart';
import '../../core/clock.dart';
import '../../domain/notebook.dart';
import '../../domain/stroke.dart';
import '../../domain/templates/paper_style.dart';

/// Scratch notebooks for rendering measurements (Ink Lab → "Perf test
/// notebooks"): a page with a little writing, two pages packed with
/// handwriting-like strokes, and a canvas with many thousands of strokes.
/// All are titled "Perf test …" and [deleteAll] removes them again.
abstract final class PerfNotebooks {
  static const Clock _clock = Clock();
  static const String prefix = 'Perf test';

  /// Creates the notebooks; returns how many strokes were written.
  static int create(AppServices services) {
    var total = 0;
    final random = math.Random(7);
    final light = _paged(services, '$prefix · light page', pages: 1);
    total += _write(services, light.first, random, lines: 4, bottom: 1123 * .3);
    final heavy = _paged(services, '$prefix · heavy page', pages: 2);
    // Leaves the lowest part of the pages empty to write in; the second
    // page is written twice as densely.
    total += _write(services, heavy[0], random, lines: 40, bottom: 1123 * .82);
    total += _write(services, heavy[1], random, lines: 80, bottom: 1123 * .82, spacing: 13.5);
    final canvas = services.notebooks.create(
      title: '$prefix · canvas',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0xFF8E8E93,
    );
    total += _write(services, canvas.id, random, lines: 160, width: 3000, bottom: 4200);
    return total;
  }

  /// Deletes every notebook whose title starts with [prefix].
  static int deleteAll(AppServices services) {
    final doomed = [
      for (final n in [...services.notebooks.list(), ...services.notebooks.trashed()])
        if (n.title.startsWith(prefix)) n.id,
    ];
    doomed.forEach(services.notebooks.delete);
    return doomed.length;
  }

  static List<String> _paged(AppServices services, String title, {required int pages}) {
    final notebook = services.notebooks.create(
      title: title,
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0xFF8E8E93,
    );
    for (var i = 1; i < pages; i++) {
      services.pages.addPage(notebook.id, paper: PaperStyle.collegeRuled);
    }
    return [for (final p in services.pages.pagesOf(notebook.id)) p.id];
  }

  /// Fills lines [spacing] units apart (27: college ruled) from the top margin down to
  /// [bottom] with words of looping cursive strokes.
  static int _write(
    AppServices services,
    String surfaceId,
    math.Random random, {
    required int lines,
    required double bottom,
    double width = 794,
    double spacing = 27,
  }) {
    final strokes = <Stroke>[];
    var time = _clock.nowMs() - 3600 * 1000;
    for (var line = 0; line < lines; line++) {
      final baseline = 80 + spacing * (line + 1) - 6;
      if (baseline > bottom) break;
      var x = 40.0 + random.nextDouble() * 20;
      while (x < width - 80) {
        final letters = 2 + random.nextInt(6);
        for (final part in _word(x, baseline, letters, random)) {
          strokes.add(
            Stroke(
              id: _clock.newId(),
              surfaceId: surfaceId,
              tool: InkTool.ballpoint,
              color: 0xFF1B1B3A,
              width: 1.6,
              points: part,
              createdAt: time += 400,
            ),
          );
        }
        x += letters * 9.0 + 10 + random.nextDouble() * 8;
      }
    }
    services.strokes.save(strokes);
    return strokes.length;
  }

  /// One word: a looping cursive body in one or two strokes, plus a dot or
  /// cross stroke now and then.
  static List<List<StrokePoint>> _word(double x0, double y0, int letters, math.Random r) {
    const a = 9 / (2 * math.pi); // Advance per radian (9 units per letter).
    final h = 9 + r.nextDouble() * 3;
    final body = <StrokePoint>[];
    final end = letters * 2 * math.pi;
    for (var s = 0.0; s <= end; s += 0.12) {
      final tall = (s / (2 * math.pi)).floor() % 3 == 1 && r.nextBool() ? 1.8 : 1.0;
      final x = x0 + a * s - 4 * math.sin(s);
      final y = y0 - h * tall * (1 - math.cos(s)) / 2 + (r.nextDouble() - .5) * .3;
      body.add(StrokePoint(x, y, .45 + .25 * math.sin(s * .7) + r.nextDouble() * .05));
    }
    final parts = <List<StrokePoint>>[];
    if (r.nextBool()) {
      // Print: a stroke per letter.
      final perLetter = body.length ~/ letters;
      for (var i = 0; i < letters; i++) {
        parts.add(body.sublist(i * perLetter, math.min(body.length, (i + 1) * perLetter + 1)));
      }
    } else {
      parts.add(body);
    }
    if (r.nextInt(3) == 0) {
      final cx = x0 + r.nextDouble() * letters * 9;
      parts.add([for (var i = 0; i <= 8; i++) StrokePoint(cx - 5 + i * 1.25, y0 - h * .8, .5)]);
    }
    return parts;
  }
}

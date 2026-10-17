@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';

import 'support/big_library.dart';

/// Making a version (the automatic recorder's work) of large notebooks: a
/// 1,000-page imported PDF with a few annotations a page, and a canvas of
/// 50,000 strokes. What counts is the longest turn of the UI thread (a
/// frame while the user may be writing; the web's 500 ms long-task rule),
/// the total, memory, and that a version after one stroke packs only what
/// changed.
void main() {
  test('1,000 PDF pages: first version, then after one stroke', () async {
    final clock = BenchClock();
    final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Reader',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final pdf = '${'ef' * 31}01';
    s.database.transaction(() {
      s.pages.insertPages(nb.id, [
        for (var i = 1; i < 1000; i++)
          (
            size: const Size(595, 842),
            paper: Paper(PaperStyle.blank),
            color: PaperColor.white,
            background: PageBackground.pdf(blob: pdf, pageIndex: i),
          ),
      ]);
      for (final p in s.pages.pagesOf(nb.id)) {
        s.strokes.save(pageOfInk(p.id, clock, lines: 1, seed: 5).take(8).toList());
      }
    });
    final page = s.pages.pagesOf(nb.id)[500];
    await _measure(s, nb.id, 'pdf 1000 pages', () {
      s.strokes.save([_stroke(page.id, clock, 9000)]);
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('canvas of 50,000 strokes: first version, then after one stroke', () async {
    final clock = BenchClock();
    final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    s.database.transaction(() {
      for (var block = 0; block < 100; block++) {
        final ink = pageOfInk(nb.id, clock, lines: 50, pointsPerStroke: 30, seed: block);
        s.strokes.save([
          for (final (i, st) in ink.take(500).indexed)
            Stroke(
              id: st.id,
              surfaceId: nb.id,
              tool: st.tool,
              color: st.color,
              width: st.width,
              points: [
                for (final p in st.points)
                  StrokePoint(p.x + (block % 10) * 700, p.y + (block ~/ 10) * 1500, p.pressure),
              ],
              createdAt: block * 1000 + i,
            ),
        ]);
      }
    });
    await _measure(s, nb.id, 'canvas 50k strokes', () {
      s.strokes.save([_stroke(nb.id, clock, 200000)]);
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Stroke _stroke(String surface, BenchClock clock, int createdAt) => Stroke(
  id: clock.newId(),
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF1F2937,
  width: 2.2,
  points: [for (var i = 0; i < 40; i++) StrokePoint(100.0 + i, 300 + math.sin(i / 3) * 7, 0.5)],
  createdAt: createdAt,
);

/// A version of [notebookId] (cold), then one after [edit], then one with
/// nothing changed: each one's total, UI turns and memory.
Future<void> _measure(AppServices s, String notebookId, String label, void Function() edit) async {
  Future<void> one(String step) async {
    final blobsBefore = _blobCount(s);
    final rss = ProcessInfo.currentRss;
    var peak = rss;
    var done = false;
    final total = Stopwatch()..start();
    final made = s.versions.record(notebookId).whenComplete(() => done = true);
    final turns = <int>[];
    final turn = Stopwatch()..start();
    while (!done) {
      await Future<void>.delayed(Duration.zero);
      turns.add(turn.elapsedMicroseconds);
      turn.reset();
      peak = math.max(peak, ProcessInfo.currentRss);
    }
    await made;
    total.stop();
    turns.sort();
    int at(double q) => turns.isEmpty ? 0 : turns[((turns.length - 1) * q).round()] ~/ 1000;
    report(
      '$label, $step: ${total.elapsedMilliseconds} ms, ${turns.length} turns '
      '(p50 ${at(.5)} ms, p99 ${at(.99)} ms, max ${at(1)} ms), '
      '${_blobCount(s) - blobsBefore} blobs written, peak RSS +${(peak - rss) >> 20} MB',
    );
  }

  await one('first version');
  edit();
  await one('after one stroke');
  await one('unchanged');
  expect(s.versions.of(notebookId), hasLength(2));
}

int _blobCount(AppServices s) =>
    s.database.db.select('SELECT COUNT(*) AS n FROM blobs').first['n'] as int;

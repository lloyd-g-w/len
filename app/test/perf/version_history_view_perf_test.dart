@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/history/version_history_sheet.dart';
import 'package:len/features/history/version_surface_view.dart';
import 'package:len/ui/app_theme.dart';

import '../support/real_async.dart';
import 'support/big_library.dart';

/// The history view of notebooks with long histories: 200 versions of a
/// 100-page notebook of handwriting (each a few strokes more on one page),
/// and a canvas of 50,000 strokes with 12 versions. What opening costs:
/// rows and thumbnails built, the UI thread's longest stretch while the
/// thumbnails on screen load, memory, and a scroll to the oldest.
void main() {
  testWidgets('200 versions of a 100-page notebook: open, thumbnails, scroll', (tester) async {
    final clock = BenchClock();
    final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Lectures',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0,
    );
    await tester.runAsync(() async {
      for (var i = 1; i < 100; i++) {
        s.pages.addPage(nb.id, paper: nb.paper);
      }
      final pages = s.pages.pagesOf(nb.id);
      s.database.transaction(() {
        for (final p in pages) {
          s.strokes.save(pageOfInk(p.id, clock, lines: 12, seed: 3));
        }
      });
      for (var v = 0; v < 200; v++) {
        s.strokes.save(pageOfInk(pages[(v * 7) % 100].id, clock, lines: 1, seed: v).take(3));
        await s.versions.record(nb.id);
      }
    });
    expect(s.versions.of(nb.id), hasLength(200));
    await _open(tester, s, nb.id, 'paged, 200 versions');
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('a canvas of 50,000 strokes with 12 versions: open, thumbnails', (tester) async {
    final clock = BenchClock();
    final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await tester.runAsync(() async {
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
      for (var v = 0; v < 12; v++) {
        s.strokes.save(pageOfInk(nb.id, clock, lines: 1, seed: v).take(3));
        await s.versions.record(nb.id);
      }
    });
    expect(s.versions.of(nb.id), hasLength(12));
    await _open(tester, s, nb.id, 'canvas 50k, 12 versions');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<void> _open(WidgetTester tester, AppServices s, String notebookId, String label) async {
  report('$label: the list read in ${bestMs(() => s.versions.of(notebookId))} ms');
  // What the thumbnails on screen load (the newest 12), with real turns.
  await tester.runAsync(() async {
    final sheets = VersionSheets(s.versions);
    final rss = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    var done = false;
    final loads = Future.wait([
      for (final v in s.versions.of(notebookId).take(12)) sheets.of(v, null),
    ]).whenComplete(() => done = true);
    final turns = await turnsUntil(() => done);
    await loads;
    turns.sort();
    report(
      '$label: 12 thumbnails loaded in ${total.elapsedMilliseconds} ms, ${turns.length} turns '
      '(p50 ${turns[turns.length ~/ 2]} ms, max ${turns.last} ms), '
      'RSS +${(ProcessInfo.currentRss - rss) >> 20} MB',
    );
  });
  tester.view
    ..physicalSize = const Size(1280, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showVersionHistory(context, s, notebookId),
              child: const Text('History'),
            ),
          ),
        ),
      ),
    ),
  );
  final rss = ProcessInfo.currentRss;
  var built = 0;
  debugOnRebuildDirtyWidget = (e, _) {
    if (e.widget is VersionSurfaceView) built++;
  };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  await tester.tap(find.text('History'));
  final open = Stopwatch()..start();
  await tester.pump();
  final firstFrame = open.elapsedMilliseconds;
  // Every pump runs what became due (the loads' zero-delay yields among
  // it), so the longest pump is the UI thread's longest stretch here.
  var longest = 0;
  var frames = 0;
  final watch = Stopwatch()..start();
  while (!_loaded()) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    final frame = Stopwatch()..start();
    await tester.pump(const Duration(milliseconds: 16));
    longest = math.max(longest, frame.elapsedMilliseconds);
    frames++;
    if (watch.elapsed > const Duration(minutes: 3)) fail('thumbnails did not load');
  }
  final loadedMs = open.elapsedMilliseconds;
  final shown = find.byType(VersionSurfaceView).evaluate().length;
  report(
    '$label: first frame $firstFrame ms; $shown thumbnails built ($built builds), loaded in '
    '$loadedMs ms over $frames frames, longest frame $longest ms; RSS +${(ProcessInfo.currentRss - rss) >> 20} MB',
  );
  // Scroll to the oldest, a screen at a time.
  final list = find.byType(Scrollable).last;
  final scroll = <int>[];
  for (var i = 0; i < 40; i++) {
    final frame = Stopwatch()..start();
    await tester.drag(list, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 16));
    scroll.add(frame.elapsedMilliseconds);
  }
  await pumpUntil(tester, _loaded, reason: 'the thumbnails after scrolling');
  scroll.sort();
  report(
    '$label: scrolling, frames median ${scroll[scroll.length ~/ 2]} ms, max ${scroll.last} ms; '
    '${find.byType(VersionSurfaceView).evaluate().length} thumbnails built at the end',
  );
}

bool _loaded() {
  final views = [
    for (final e in find.byType(VersionSurfaceView).evaluate())
      (e as StatefulElement).state as VersionSurfaceViewState,
  ];
  return views.isNotEmpty && views.every((v) => v.loaded);
}

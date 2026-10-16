@Tags(['perf'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/features/editor/document/page_thumbnail.dart';
import 'package:len/ui/app_theme.dart';

import 'support/big_library.dart';

/// The page overview of a 500-page notebook of handwriting, scrolled: a
/// fast drag, a fling and a slow drag. Thumbnails wait while the grid
/// scrolls fast and are recorded where it settles; a slow scroll never
/// shows a tile blank for more than the frame it came in.
///
/// Run: `tool/light.sh flutter test test/perf/overview_scroll_perf_test.dart`.
void main() {
  testWidgets('overview, 500 pages: one fast drag', (tester) async {
    final (s, cache) = await _open(tester);
    final rss = ProcessInfo.currentRss;
    final frames = <int>[];
    final before = cache.recordings;
    // One long, fast drag (25,000 px/s) that stops mid-grid, then letting go.
    final drag = await tester.startGesture(tester.getCenter(find.byType(Scrollable).first));
    for (var i = 0; i < 60; i++) {
      final frame = Stopwatch()..start();
      await drag.moveBy(const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(frame.elapsedMilliseconds);
    }
    final during = cache.recordings - before;
    await drag.up();
    await tester.pumpAndSettle();
    final after = cache.recordings - before - during;
    frames.sort();
    final built = find.byType(PageThumbnail, skipOffstage: false).evaluate().length;
    expect(built, lessThan(80), reason: 'a lazy grid');
    expect(_blank(tester, cache), isEmpty, reason: 'settled: every tile on screen recorded');
    report(
      'overview, 500 pages, fast drag: frames median ${frames[frames.length ~/ 2]}ms, max '
      '${frames.last}ms; $during pages recorded while dragging, $after once settled; '
      '$built thumbnails built; RSS +${(ProcessInfo.currentRss - rss) >> 20} MB',
    );
    await _close(tester, s);
  });

  testWidgets('overview, 500 pages: a fling', (tester) async {
    final (s, cache) = await _open(tester);
    final before = cache.recordings;
    final frames = <int>[];
    final start = tester.getCenter(find.byType(Scrollable).first);
    await tester.flingFrom(start, const Offset(0, -600), 12000);
    var settledAt = 0;
    for (var i = 0; i < 400 && tester.binding.hasScheduledFrame; i++) {
      final frame = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(frame.elapsedMilliseconds);
      if (settledAt == 0 && cache.recordings > before) settledAt = i;
    }
    await tester.pumpAndSettle();
    frames.sort();
    expect(_blank(tester, cache), isEmpty, reason: 'settled: every tile on screen recorded');
    report(
      'overview, 500 pages, fling at 12,000 px/s: ${frames.length} frames, median '
      '${frames[frames.length ~/ 2]}ms, max ${frames.last}ms; first page recorded at frame '
      '$settledAt; ${cache.recordings - before} recorded in all',
    );
    await _close(tester, s);
  });

  testWidgets('overview, 500 pages: a slow drag shows no blank tiles', (tester) async {
    final (s, cache) = await _open(tester);
    final frames = <int>[];
    final blankFor = <String, int>{};
    var longestBlank = 0;
    // 300 px/s: reading the thumbnails while scrolling.
    final drag = await tester.startGesture(tester.getCenter(find.byType(Scrollable).first));
    for (var i = 0; i < 180; i++) {
      final frame = Stopwatch()..start();
      await drag.moveBy(const Offset(0, -5));
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(frame.elapsedMilliseconds);
      final blank = _blank(tester, cache);
      blankFor.removeWhere((id, _) => !blank.contains(id));
      for (final id in blank) {
        final n = blankFor[id] = (blankFor[id] ?? 0) + 1;
        if (n > longestBlank) longestBlank = n;
      }
    }
    await drag.up();
    await tester.pumpAndSettle();
    frames.sort();
    report(
      'overview, 500 pages, slow drag (300 px/s): frames median ${frames[frames.length ~/ 2]}ms, '
      'max ${frames.last}ms; a tile blank for at most $longestBlank frame(s)',
    );
    expect(longestBlank, lessThanOrEqualTo(1), reason: 'recorded the frame after it came in');
    await _close(tester, s);
  });
}

Future<(AppServices, ThumbnailCache)> _open(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1200, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (s, nb) = lectureNotebook();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: PageOverview(
        currentPage: 0,
        copier: SurfaceCopier(s.strokes, elements: s.elements),
        handlers: OverviewHandlers(
          load: () => s.pages.pagesOf(nb.id),
          move: s.pages.move,
          command: (context, command, page) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final cache = tester.widget<PageThumbnail>(find.byType(PageThumbnail).first).cache;
  return (s, cache);
}

/// Pages of the thumbnails on screen whose ink is not recorded yet.
Set<String> _blank(WidgetTester tester, ThumbnailCache cache) => {
  for (final e in find.byType(PageThumbnail).evaluate())
    if (!cache.isRecorded((e.widget as PageThumbnail).page.id)) (e.widget as PageThumbnail).page.id,
};

Future<void> _close(WidgetTester tester, AppServices s) async {
  await tester.pumpWidget(const SizedBox());
  s.dispose();
}

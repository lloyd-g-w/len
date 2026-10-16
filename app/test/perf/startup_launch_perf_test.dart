@Tags(['perf'])
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_reader.dart';
import 'package:len/domain/chunk_digest.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/ink/render/outline_preparer.dart';

import 'support/big_library.dart';
import 'support/startup_library.dart';

/// A launch as `main` does it (open the database, create the services,
/// the app's first frame), with the library of `StartupLibrary` (300
/// notebooks, a 500-page notebook of handwriting left open) against a
/// smaller one (120 notebooks: as many cards on screen; the notebook left
/// open has 5 pages): nothing
/// before the first frame may grow with the library or the notebook, and
/// a kept workspace is the first frame, the library under it untouched.
/// (Debug JIT in the harness: compared with each other, never with frame
/// budgets; best of interleaved rounds.)
void main() {
  testWidgets('launch: nothing before the first frame grows with the library', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final big = _Library(notebooks: 300, pages: 500);
    final small = _Library(notebooks: 120, pages: 5);
    addTearDown(big.files.dispose);
    addTearDown(small.files.dispose);

    final best = <String, double>{};
    void keep(String key, double ms) => best[key] = math.min(best[key] ?? double.infinity, ms);
    for (var round = 0; round < 4; round++) {
      for (final (name, library) in [('big', big), ('small', small)]) {
        for (final restore in [true, false]) {
          final t = await _launch(tester, library, restore: restore);
          // The first round compiles and loads much: left out.
          if (round == 0) continue;
          final what = restore ? 'restore' : 'library';
          keep('$name open', t.open);
          keep('$name services', t.services);
          keep('$name $what frame', t.frame);
        }
      }
    }
    report(
      'launch (best ms): ${best.map((k, v) => MapEntry(k, v.toStringAsFixed(1)))}; '
      'big: ${big.strokes} strokes, ${big.files.dbBytes >> 20} MB',
    );
    void notMuchMore(String what, {double factor = 1.3, double slack = 15}) => expect(
      best['big $what']!,
      lessThan(best['small $what']! * factor + slack),
      reason: '$what grows with the library',
    );
    notMuchMore('open', factor: 1.5);
    notMuchMore('services', factor: 1.5, slack: 10);
    notMuchMore('restore frame');
    notMuchMore('library frame');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// A library in a database file, with a workspace kept in its notebook of
/// [pages] pages.
class _Library {
  _Library({required int notebooks, required int pages}) {
    final clock = BenchClock();
    final s = openServices(files.dbPath, clock);
    StartupLibrary.build(s, clock, notebookCount: notebooks, lecturePages: pages);
    workspace = s.settings.workspace!;
    strokes = s.database.db.select('SELECT COUNT(*) AS n FROM strokes').first['n'] as int;
    s.database.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    s.dispose();
  }

  final files = BenchFiles();
  late final String workspace;
  late final int strokes;
}

/// Launches the app on [library] (with its workspace if [restore], else
/// on the library) and closes it again; returns the milliseconds each step
/// took on the UI thread.
Future<({double open, double services, double frame})> _launch(
  WidgetTester tester,
  _Library library, {
  required bool restore,
}) async {
  double ms(Stopwatch w) => w.elapsedMicroseconds / 1000;
  final w = Stopwatch()..start();
  final database = await AppDatabase.openDefault(library.files.dir.path);
  final open = ms(w);
  w.reset();
  // Natively ink arrives from the reader isolate, outlined on workers,
  // after the first frame.
  final services = AppServices.create(
    database,
    strokeReader: const _NotYet(),
    outlines: const _OutlinesNotYet(),
  );
  final created = ms(w);
  // Leaving the editor forgot it: the workspace as the last launch left it.
  services.settings.workspace = restore ? library.workspace : null;
  w.reset();
  await tester.pumpWidget(LenApp(services: services));
  final frame = ms(w);
  expect(find.byType(EditorScreen), restore ? findsOneWidget : findsNothing);
  if (restore) {
    // The library under the editor builds no cards (renders no covers).
    expect(find.byType(NotebookCard, skipOffstage: false), findsNothing);
  } else {
    expect(find.byType(NotebookCard), findsWidgets);
  }
  await tester.pumpWidget(const SizedBox());
  services.dispose();
  return (open: open, services: created, frame: frame);
}

/// A reader that hasn't answered yet: the background isolate's answers
/// come after the first frame.
class _NotYet implements StrokeReader {
  const _NotYet();

  @override
  Future<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) =>
      Completer<ChunkLoad>().future;

  @override
  Future<Map<ChunkKey, ChunkDigest>> chunkDigests(String surfaceId, ChunkRange range) =>
      Completer<Map<ChunkKey, ChunkDigest>>().future;

  @override
  Future<Map<ChunkKey, int>> chunkDensity(String surfaceId) =>
      Completer<Map<ChunkKey, int>>().future;

  @override
  Future<Rect?> contentBounds(String surfaceId) => Completer<Rect?>().future;
}

/// Outlines built on workers: not before the first frame.
class _OutlinesNotYet implements OutlinePreparer {
  const _OutlinesNotYet();

  @override
  Future<void> prepare(List<Stroke> strokes, {void Function(List<Stroke> ready)? onReady}) =>
      Completer<void>().future;

  @override
  void close() {}
}

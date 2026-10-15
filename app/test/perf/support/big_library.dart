import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/folder.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/ui/app_theme.dart' show Palette;
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';
import 'package:uuid/uuid.dart';

/// Real-looking ids (UUID v4 from a seeded generator) and a clock that
/// moves a minute per call, so years of history fit in one run.
class BenchClock extends Clock {
  BenchClock([int seed = 7]) : _rng = MathRNG(seed: seed);

  final MathRNG _rng;
  int now = DateTime(2023, 1, 1).millisecondsSinceEpoch;

  @override
  int nowMs() => now += 60000;

  @override
  String newId() => _uuid.v4(config: V4Options(null, _rng));
  static const _uuid = Uuid();
}

/// A database file in a fresh temporary directory (deleted by [dispose]).
class BenchFiles {
  BenchFiles() : dir = Directory.systemTemp.createTempSync('len-perf-');

  final Directory dir;

  String get dbPath => '${dir.path}/len.db';

  int get dbBytes => [
    for (final f in dir.listSync())
      if (f is File && f.path.contains('len.db')) f.lengthSync(),
  ].fold(0, (a, b) => a + b);

  void dispose() => dir.deleteSync(recursive: true);
}

const _words = [
  'meeting',
  'project',
  'chapter',
  'exercise',
  'summary',
  'theorem',
  'velocity',
  'protein',
  'budget',
  'design',
  'review',
  'history',
  'language',
  'garden',
  'recipe',
  'travel',
  'invoice',
  'lecture',
  'question',
  'answer',
  'diagram',
  'molecule',
  'energy',
  'market',
  'strategy',
  'poetry',
  'novel',
  'grammar',
  'integral',
  'matrix',
  'circuit',
  'planet',
  'climate',
  'economy',
  'museum',
  'concert',
  'training',
  'workout',
  'journal',
  'a',
  'the',
  'and',
  'of',
  'to',
  'in',
  'is',
  'for',
  'with',
  'on',
  'notes',
  'idea',
];

/// Deterministic prose of [count] words.
String prose(math.Random r, int count) =>
    [for (var i = 0; i < count; i++) _words[r.nextInt(_words.length)]].join(' ');

/// Strokes that fill a ruled A4 page with writing: [lines] lines of words
/// of [pointsPerStroke] points each (≈ 9 words a line).
List<Stroke> pageOfInk(
  String surface,
  Clock clock, {
  int lines = 25,
  int pointsPerStroke = 40,
  int seed = 1,
}) {
  final r = math.Random(seed);
  final strokes = <Stroke>[];
  for (var line = 0; line < lines; line++) {
    final y = 120 + line * 28.0;
    var x = 80.0;
    while (x < 520) {
      final w = 20 + r.nextDouble() * 40;
      strokes.add(
        Stroke(
          id: clock.newId(),
          surfaceId: surface,
          tool: InkTool.ballpoint,
          color: 0xFF1F2937,
          width: 2.2,
          points: [
            for (var i = 0; i < pointsPerStroke; i++)
              StrokePoint(
                x + w * i / pointsPerStroke,
                y + math.sin(i / 3 + r.nextDouble()) * 7,
                0.4 + 0.3 * r.nextDouble(),
              ),
          ],
          createdAt: strokes.length,
        ),
      );
      x += w + 12;
    }
  }
  return strokes;
}

/// A 500-page notebook of handwriting.
(AppServices, Notebook) lectureNotebook({int pages = 500, int lines = 20}) {
  final clock = BenchClock();
  final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  final nb = s.notebooks.create(
    title: 'Lectures',
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
  );
  s.database.transaction(() {
    s.pages.insertPages(nb.id, [
      for (var i = 1; i < pages; i++)
        (
          size: const Size(595, 842),
          paper: Paper(PaperStyle.collegeRuled),
          color: PaperColor.white,
          background: null,
        ),
    ]);
    for (final p in s.pages.pagesOf(nb.id)) {
      s.strokes.save(pageOfInk(p.id, clock, lines: lines, seed: 3));
    }
  });
  return (s, nb);
}

/// What [BigLibrary.build] made.
class BigLibrary {
  BigLibrary._(this.folders, this.notebooks, this.trashed, this.pdfBlob);

  final List<Folder> folders;
  final List<Notebook> notebooks;
  final List<Notebook> trashed;
  final String pdfBlob;

  /// Fills [s] with a years-old library: [folderCount] folders (a fifth at
  /// the top level), [notebookCount] notebooks spread over them (every
  /// tenth a favourite, the last [trashCount] in the trash), each with
  /// [pagesPerNotebook] pages holding a text box of prose; every fifth
  /// notebook is an imported PDF (its pages' text in `pdf_text`); the first
  /// page of every notebook has [coverLines] lines of handwriting.
  static BigLibrary build(
    AppServices s,
    Clock clock, {
    int folderCount = 50,
    int notebookCount = 1000,
    int trashCount = 200,
    int pagesPerNotebook = 10,
    int coverLines = 4,
    int wordsPerPage = 60,
  }) {
    final r = math.Random(11);
    final folders = <Folder>[];
    final notebooks = <Notebook>[];
    final trashed = <Notebook>[];
    final pdfBlob = '${'ab' * 31}cd';
    s.database.transaction(() {
      for (var i = 0; i < folderCount; i++) {
        final parent = i < folderCount ~/ 5 || folders.isEmpty
            ? null
            : folders[r.nextInt(folderCount ~/ 5)].id;
        folders.add(
          s.folders.create(name: 'Folder $i ${_words[i % 39]}', parentId: parent, color: 0),
        );
      }
      final pdfPages = pagesPerNotebook;
      for (var p = 0; p < pdfPages; p++) {
        s.database.db.execute('INSERT INTO pdf_text (blob, page, text) VALUES (?, ?, ?)', [
          pdfBlob,
          p,
          prose(r, wordsPerPage * 3),
        ]);
      }
      s.database.db.execute('INSERT INTO pdf_text_blobs (blob, pages, ok) VALUES (?, ?, 1)', [
        pdfBlob,
        pdfPages,
      ]);
      for (var i = 0; i < notebookCount; i++) {
        final pdf = i % 5 == 4;
        final n = s.notebooks.create(
          title: '${_words[i % 39]} ${2023 + i % 4} — notebook $i',
          kind: NotebookKind.paged,
          paper: PaperStyle.collegeRuled,
          coverColor: Palette.covers[i % Palette.covers.length],
          folderId: i % 7 == 0 ? null : folders[r.nextInt(folders.length)].id,
        );
        final first = s.pages.pagesOf(n.id).single;
        final more = s.pages.insertPages(n.id, [
          for (var p = 1; p < pagesPerNotebook; p++)
            (
              size: const Size(595, 842),
              paper: Paper(PaperStyle.collegeRuled),
              color: PaperColor.white,
              background: pdf ? PageBackground.pdf(blob: pdfBlob, pageIndex: p) : null,
            ),
        ]);
        s.elements.save([
          for (final page in [first, ...more])
            if (!pdf)
              SurfaceElement(
                id: clock.newId(),
                surfaceId: page.id,
                type: 'text',
                rect: const Rect.fromLTWH(80, 600, 400, 160),
                z: 1,
                createdAt: clock.nowMs(),
                data: {'text': prose(r, wordsPerPage), 'size': 16},
              ),
        ]);
        if (coverLines > 0) s.strokes.save(pageOfInk(first.id, clock, lines: coverLines, seed: i));
        if (i % 10 == 3) s.notebooks.setFavorite(n.id, true);
        notebooks.add(n);
      }
      for (final n in notebooks.sublist(notebookCount - trashCount)) {
        s.notebooks.trash(n.id);
        trashed.add(n);
      }
    });
    return BigLibrary._(folders, notebooks, trashed, pdfBlob);
  }
}

/// Opens services on the database file at [path] (as the app does).
AppServices openServices(String path, Clock clock) =>
    AppServices.create(AppDatabase.open(path), clock: clock);

/// Milliseconds [action] takes (best of [runs]).
int bestMs(void Function() action, {int runs = 3}) {
  var best = 1 << 30;
  for (var i = 0; i < runs; i++) {
    final w = Stopwatch()..start();
    action();
    best = math.min(best, w.elapsedMilliseconds);
  }
  return best;
}

/// Microseconds [action] takes (best of [runs]).
int bestUs(void Function() action, {int runs = 3}) {
  var best = 1 << 30;
  for (var i = 0; i < runs; i++) {
    final w = Stopwatch()..start();
    action();
    best = math.min(best, w.elapsedMicroseconds);
  }
  return best;
}

/// Lets the event loop run until [done], returning the longest time (ms)
/// one turn of it took: how long work in between blocked the UI thread.
Future<int> longestTurnUntil(bool Function() done) async =>
    (await turnsUntil(done)).fold<int>(0, math.max);

/// Lets the event loop run until [done]; returns how long (ms) each of its
/// turns took.
Future<List<int>> turnsUntil(bool Function() done) async {
  final turns = <int>[];
  final turn = Stopwatch()..start();
  while (!done()) {
    await Future<void>.delayed(Duration.zero);
    turns.add(turn.elapsedMilliseconds);
    turn.reset();
  }
  return turns;
}

// ignore: avoid_print
void report(String line) => print(line);

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';

import '../../data/app_database.dart';
import '../../data/search/ink_text_boxes.dart';
import '../../data/stroke_queries.dart';
import 'handwriting_recognizer.dart';
import 'ink_clustering.dart';

/// Recognises handwriting in the background and stores it in `ink_text`
/// (see `InkTextSchema`), which triggers feed into the search index.
///
/// Work comes from `ink_text_queue`, which triggers on `strokes` fill on
/// every change — local edits, undo, sync — so nothing has to call in.
/// The indexer wakes on database commits (when [start]ed), waits until the
/// database has been quiet for [idleDelay] (the user stopped writing), and
/// then works through the queue one surface at a time, one line at a time,
/// pausing again whenever new edits arrive. Lines whose strokes did not
/// change keep their earlier result, so adding a word re-recognises just
/// that line.
class HandwritingIndexer extends ChangeNotifier {
  HandwritingIndexer(
    this.database, {
    required this.recognizer,
    required this.language,
    this.idleDelay = const Duration(seconds: 3),
    this.pauseBetweenLines = const Duration(milliseconds: 15),
    Stream<void>? commits,
  }) : _commitSource = commits;

  final AppDatabase database;
  final HandwritingRecognizer recognizer;

  /// The language to recognise in (read at the start of each surface).
  final String Function() language;

  /// How long the database must be quiet before (and while) indexing.
  final Duration idleDelay;

  /// A breather between recognised lines, to stay light on the device.
  final Duration pauseBetweenLines;

  final Stream<void>? _commitSource;

  /// Called after recognised text was added or removed (e.g. so open
  /// searches refresh).
  VoidCallback? onIndexed;

  CommonDatabase get _db => database.db;

  StreamSubscription<void>? _commits;
  Timer? _timer;
  bool _running = false;
  bool _active = false;
  bool _disposed = false;
  int _ownCommits = 0;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  String? _current;
  Object? _lastError;

  /// Whether the indexer is watching for changes.
  bool get isActive => _active;

  /// Whether a surface is being recognised right now.
  bool get isIndexing => _current != null;

  /// The last recognition failure (cleared by a successful surface).
  Object? get lastError => _lastError;

  /// Surfaces waiting to be (re-)recognised.
  int get pendingCount => _db.select('SELECT COUNT(*) AS n FROM ink_text_queue').first['n'] as int;

  /// Number of recognised lines stored.
  int get lineCount => _db.select('SELECT COUNT(*) AS n FROM ink_text').first['n'] as int;

  /// Starts watching for changes and indexes what is queued (after
  /// [idleDelay]).
  void start() {
    if (_active || _disposed) return;
    _active = true;
    _ownCommits = 0;
    _commits = (_commitSource ?? _db.commits).listen((_) => _onCommit());
    schedule();
    notifyListeners();
  }

  /// Stops watching; a surface being recognised finishes its current line.
  void stop() {
    if (!_active) return;
    _active = false;
    _timer?.cancel();
    unawaited(_commits?.cancel());
    _commits = null;
    notifyListeners();
  }

  /// Runs the queue once the database has been quiet for [idleDelay].
  void schedule() {
    if (!_active || _disposed) return;
    _timer?.cancel();
    _timer = Timer(idleDelay, () => unawaited(run()));
  }

  /// Works through the queue now (respecting quiet time between lines);
  /// completes when it is empty, or on stop or failure.
  Future<void> run() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (_active && !_disposed) {
        final next = _db.select(
          'SELECT surface_id, version FROM ink_text_queue ORDER BY version LIMIT 1',
        );
        if (next.isEmpty) break;
        final surface = next.first['surface_id'] as String;
        final version = next.first['version'] as int;
        _current = surface;
        notifyListeners();
        try {
          await indexSurface(surface, version: version);
          _lastError = null;
        } on Object catch (e) {
          // Model missing or the engine failed: try again on the next change.
          debugPrint('Handwriting recognition failed on $surface: $e');
          _lastError = e;
          break;
        }
      }
    } finally {
      _running = false;
      _current = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Recognises the lines of [surfaceId] that changed and stores the
  /// result; removes the surface from the queue if it is still at
  /// [version] (a change made meanwhile keeps it queued).
  Future<void> indexSurface(String surfaceId, {int? version}) async {
    final lang = language();
    final strokes = _db
        .select('SELECT * FROM strokes WHERE surface_id = ? AND deleted = 0', [surfaceId])
        .map(StrokeQueries.rowToStroke)
        .nonNulls;
    final lines = InkClustering.lines(strokes);
    final existing = <String, ({int id, String text})>{
      for (final r in _db.select(
        'SELECT id, stroke_key, text FROM ink_text WHERE surface_id = ? AND language = ?',
        [surfaceId, lang],
      ))
        r['stroke_key'] as String: (id: r['id'] as int, text: r['text'] as String),
    };
    final keep = <int>{};
    final fresh = <({InkLine line, String text, List<Rect>? words})>[];
    var before = '';
    for (final line in lines) {
      if (_disposed) return;
      final known = existing[line.key];
      if (known != null) {
        keep.add(known.id);
        before = known.text;
        continue;
      }
      await _untilQuiet();
      if (_disposed) return;
      final candidates = await recognizer.recognize(
        line.strokes,
        language: lang,
        writingArea: Size(line.bounds.width + line.letterHeight, line.letterHeight * 2.5),
        preContext: _tail(before),
      );
      final text = (candidates.firstOrNull?.text ?? '').trim();
      before = text;
      fresh.add((line: line, text: text, words: wordBoxes(line, text)));
    }
    if (_disposed) return;
    var changed = fresh.isNotEmpty;
    _ownTransaction(() {
      final stale = [
        for (final r in _db.select('SELECT id FROM ink_text WHERE surface_id = ?', [surfaceId]))
          if (!keep.contains(r['id'])) r['id'] as int,
      ];
      if (stale.isNotEmpty) changed = true;
      for (final id in stale) {
        _db.execute('DELETE FROM ink_text WHERE id = ?', [id]);
      }
      for (final f in fresh) {
        final b = f.line.bounds;
        _db.execute(
          'INSERT INTO ink_text (surface_id, stroke_key, language, text, x, y, w, h, words) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            surfaceId,
            f.line.key,
            lang,
            f.text,
            b.left,
            b.top,
            b.width,
            b.height,
            InkTextBoxes.encode(f.words),
          ],
        );
      }
      _db.execute(
        'DELETE FROM ink_text_queue WHERE surface_id = ? ${version == null ? '' : 'AND version = ?'}',
        [surfaceId, ?version],
      );
    });
    notifyListeners();
    if (changed) onIndexed?.call();
  }

  /// Boxes for the words of [text] if the line has as many word clusters
  /// as the text has words (else null: the line is highlighted whole).
  static List<Rect>? wordBoxes(InkLine line, String text) {
    final count = InkTextBoxes.wordRanges(text).length;
    if (count == 0 || count != line.words.length) return null;
    return [for (final w in line.words) w.bounds];
  }

  static String _tail(String text) => text.length <= 20 ? text : text.substring(text.length - 20);

  Future<void> _untilQuiet() async {
    if (pauseBetweenLines > Duration.zero) await Future<void>.delayed(pauseBetweenLines);
    while (!_disposed) {
      final quietFor = DateTime.now().difference(_lastActivity);
      if (quietFor >= idleDelay) return;
      await Future<void>.delayed(idleDelay - quietFor);
    }
  }

  /// Runs [action] in a transaction whose commit [_onCommit] ignores.
  void _ownTransaction(void Function() action) {
    final watched = _commits != null;
    if (watched) _ownCommits++;
    try {
      database.transaction(action);
    } catch (_) {
      if (watched) _ownCommits--;
      rethrow;
    }
  }

  void _onCommit() {
    if (_ownCommits > 0) {
      _ownCommits--;
      return;
    }
    _lastActivity = DateTime.now();
    // A cheap check: most commits do not touch ink.
    if (!_running) schedule();
  }

  /// Forgets all recognised text (indexing switched off).
  void clear() {
    _ownTransaction(() => _db.execute('DELETE FROM ink_text'));
    notifyListeners();
    onIndexed?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

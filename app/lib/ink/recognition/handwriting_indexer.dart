import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';

import '../../core/pointer_activity.dart';
import '../../data/app_database.dart';
import '../../data/recognised_text_repository.dart';
import '../../data/search/ink_text_boxes.dart';
import '../../data/stroke_queries.dart';
import '../lab/perf_probe.dart';
import 'handwriting_recognizer.dart';
import 'ink_clustering.dart';

part 'handwriting_indexer_steps.dart';

/// Recognises handwriting in the background and stores it in `ink_text`
/// (see `InkTextSchema`), which triggers feed into the search index.
///
/// Work comes from `ink_text_queue`, which triggers on `strokes` fill on
/// every change — local edits, undo, sync — so nothing has to call in.
/// The indexer wakes on database commits (when [start]ed), waits until the
/// database has been quiet for [idleDelay] (the user stopped writing), and
/// then works through the queue one surface at a time, one line at a time,
/// pausing again whenever new edits arrive. With [activity] it also waits
/// while a pointer is down (writing — strokes reach the database only at
/// pen-up —, scrolling, zooming) and for [idleDelay] after the last one, so
/// no recognition work starts while the user interacts. Lines whose strokes did not
/// change keep their earlier result, so adding a word re-recognises just
/// that line; lines another device recognised (synced, see
/// [RecognisedTextRepository]) are not recognised again. Without a
/// recogniser (Linux, Windows, web) it indexes only text synced from
/// devices with one.
class HandwritingIndexer extends ChangeNotifier {
  HandwritingIndexer(
    this.database, {
    required this.recognizer,
    required this.shared,
    required this.language,
    int Function()? languageChangedAt,
    this.idleDelay = const Duration(seconds: 3),
    this.pauseBetweenLines = const Duration(milliseconds: 15),
    this.activity,
    Stream<void>? commits,
  }) : _commitSource = commits,
       languageChangedAt = languageChangedAt ?? (() => 0);

  final AppDatabase database;

  /// Recognises lines; an unsupported one ([HandwritingRecognizer.isSupported]
  /// false) makes this an indexer of text recognised elsewhere ([shared]).
  final HandwritingRecognizer recognizer;

  /// Recognised text synced between devices.
  final RecognisedTextRepository shared;

  /// The language to recognise in (read at the start of each surface).
  final String Function() language;

  /// When the user last chose [language] (ms; see
  /// [RecognisedTextRepository.publish]).
  final int Function() languageChangedAt;

  /// How long the database must be quiet before (and while) indexing.
  final Duration idleDelay;

  /// A breather between recognised lines, to stay light on the device.
  final Duration pauseBetweenLines;

  /// The user's pointer activity, which defers work like database commits.
  final PointerActivity? activity;

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
    _commits = (_commitSource ?? database.commits).listen((_) => _onCommit());
    if (_hasWork) schedule();
    notifyListeners();
  }

  /// Whether a queued surface may need work. Without a recogniser only
  /// surfaces with synced text do (the others are dropped from the queue
  /// whenever a run happens), so a device that never received any does not
  /// even wake up.
  bool get _hasWork => database
      .select(
        recognizer.isSupported
            ? 'SELECT 1 FROM ink_text_queue LIMIT 1'
            : 'SELECT 1 FROM ink_text_queue q JOIN recognised_text r ON r.id = q.surface_id '
                  'LIMIT 1',
      )
      .isNotEmpty;

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
        // Clustering a surface is UI-thread work too.
        await _untilQuiet(pause: false);
        if (!_active || _disposed) break;
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

  /// Brings the recognised text of [surfaceId] up to date and removes the
  /// surface from the queue if it is still at [version] (a change made
  /// meanwhile keeps it queued).
  ///
  /// Each line keeps its earlier text while its strokes are unchanged, else
  /// takes the text another device synced for the same strokes, else (with
  /// a recogniser) is recognised. With a recogniser, the result is synced
  /// ([RecognisedTextRepository.publish]); without one, only synced lines
  /// get text.
  Future<void> indexSurface(String surfaceId, {int? version}) async {
    final lang = language();
    final recognise = recognizer.isSupported;
    final synced = shared.read(surfaceId);
    // Without a recogniser and nothing synced, no line can have text.
    final lines = recognise || synced != null ? _cluster(surfaceId) : const <InkLine>[];
    final existing = <String, ({int id, String text, String language})>{
      for (final r in _db.select(
        'SELECT id, stroke_key, text, language FROM ink_text WHERE surface_id = ?',
        [surfaceId],
      ))
        r['stroke_key'] as String: (
          id: r['id'] as int,
          text: r['text'] as String,
          language: r['language'] as String,
        ),
    };
    final keep = <int>{};
    final fresh = <({InkLine line, String text, String language})>[];
    final read = <String, String>{};
    var before = '';
    for (final line in lines) {
      if (_disposed) return;
      final local = existing[line.key];
      final elsewhere = synced?.lines[line.key];
      final String text, textLanguage;
      if (!recognise) {
        if (elsewhere == null) continue;
        (text, textLanguage) = (elsewhere, synced!.language);
      } else if (local != null && local.language == lang) {
        (text, textLanguage) = (local.text, lang);
      } else if (elsewhere != null && synced!.language == lang) {
        (text, textLanguage) = (elsewhere, lang);
      } else {
        await _untilQuiet();
        if (_disposed) return;
        final candidates = await recognizer.recognize(
          line.strokes,
          language: lang,
          writingArea: Size(line.bounds.width + line.letterHeight, line.letterHeight * 2.5),
          preContext: _tail(before),
        );
        (text, textLanguage) = ((candidates.firstOrNull?.text ?? '').trim(), lang);
      }
      if (local != null && local.text == text && local.language == textLanguage) {
        keep.add(local.id);
      } else {
        fresh.add((line: line, text: text, language: textLanguage));
      }
      read[line.key] = text;
      before = text;
    }
    if (_disposed) return;
    final removed = _store(
      surfaceId,
      keep: keep,
      fresh: fresh,
      read: read,
      lang: lang,
      recognise: recognise,
      version: version,
    );
    notifyListeners();
    if (fresh.isNotEmpty || removed) onIndexed?.call();
  }

  /// Boxes for the words of [text] if the line has as many word clusters
  /// as the text has words (else null: the line is highlighted whole).
  static List<Rect>? wordBoxes(InkLine line, String text) {
    final count = InkTextBoxes.wordRanges(text).length;
    if (count == 0 || count != line.words.length) return null;
    return [for (final w in line.words) w.bounds];
  }

  static String _tail(String text) => text.length <= 20 ? text : text.substring(text.length - 20);

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

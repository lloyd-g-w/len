part of 'handwriting_indexer.dart';

/// How long [HandwritingIndexer] waits between checks while a pointer is down.
const _busyPoll = Duration(milliseconds: 250);

/// The indexer's steps: clustering, storing, waiting for quiet, and
/// telling its own commits from others.
extension _IndexerSteps on HandwritingIndexer {
  /// Stores what [indexSurface] found for [surfaceId]: removes the lines
  /// not in [keep], inserts [fresh], publishes [read] (when it was
  /// [recognise]d in [lang]) and dequeues the surface if still at
  /// [version]. Returns whether any line was removed.
  bool _store(
    String surfaceId, {
    required Set<int> keep,
    required List<({InkLine line, String text, String language})> fresh,
    required Map<String, String> read,
    required String lang,
    required bool recognise,
    int? version,
  }) {
    var removed = false;
    _ownTransaction(() {
      final stale = [
        for (final r in _db.select('SELECT id FROM ink_text WHERE surface_id = ?', [surfaceId]))
          if (!keep.contains(r['id'])) r['id'] as int,
      ];
      if (stale.isNotEmpty) removed = true;
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
            f.language,
            f.text,
            b.left,
            b.top,
            b.width,
            b.height,
            InkTextBoxes.encode(HandwritingIndexer.wordBoxes(f.line, f.text)),
          ],
        );
      }
      if (recognise) shared.publish(surfaceId, lang, read, languageChangedAt: languageChangedAt());
      _db.execute(
        'DELETE FROM ink_text_queue WHERE surface_id = ? ${version == null ? '' : 'AND version = ?'}',
        [surfaceId, ?version],
      );
    });
    return removed;
  }

  /// The lines of the live strokes on [surfaceId].
  List<InkLine> _cluster(String surfaceId) {
    developer.Timeline.startSync('len.handwritingCluster');
    final strokes = _db
        .select('SELECT * FROM strokes WHERE surface_id = ? AND deleted = 0', [surfaceId])
        .map(StrokeQueries.rowToStroke)
        .nonNulls;
    final watch = Stopwatch()..start();
    final lines = InkClustering.lines(strokes);
    PerfProbe.count('handwritingClusterMs', watch.elapsedMilliseconds);
    developer.Timeline.finishSync();
    return lines;
  }

  /// Waits (after [pauseBetweenLines] if [pause]) until neither the
  /// database nor the pointers ([activity]) saw activity for [idleDelay].
  Future<void> _untilQuiet({bool pause = true}) async {
    if (pause && pauseBetweenLines > Duration.zero) {
      await Future<void>.delayed(pauseBetweenLines);
    }
    while (!_disposed) {
      final pointers = activity;
      final busy = pointers != null && pointers.isActive;
      var last = _lastActivity;
      if (pointers != null && pointers.lastActivity.isAfter(last)) last = pointers.lastActivity;
      final quietFor = DateTime.now().difference(last);
      if (!busy && quietFor >= idleDelay) return;
      // While a pointer is down, poll: its release is not a commit.
      final wait = busy ? _busyPoll : idleDelay - quietFor;
      await Future<void>.delayed(wait > Duration.zero ? wait : _busyPoll);
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
    if (!_running && (_timer?.isActive == true || _hasWork)) schedule();
  }
}

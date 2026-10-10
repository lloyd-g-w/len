import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../app_database.dart';
import 'pdf_text_source.dart';
import 'search_schema.dart';

/// Extracts the text of imported PDFs into the search index, in the
/// background: one PDF at a time, a few pages per database transaction,
/// PDFium working off the UI thread (pdfrx runs it in a worker), so the UI
/// never waits. Each PDF blob is read once, however many pages or
/// notebooks show it; an interrupted run resumes where it stopped.
///
/// Runs when [schedule]d — after an import, before a search, or after sync
/// brought pages — and only for blobs present on this device (they are
/// fetched lazily when a page is viewed; later runs pick them up).
class PdfTextIndexer extends ChangeNotifier {
  PdfTextIndexer(
    this.database, {
    required this.readBlob,
    this.source = const PdfrxTextSource(),
    this.batchSize = 8,
  });

  final AppDatabase database;

  /// The bytes of a blob, or null if it is not on this device.
  final Future<Uint8List?> Function(String sha) readBlob;
  final PdfTextSource source;

  /// Pages written per transaction (and per notification).
  final int batchSize;

  Database get _db => database.db;

  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  /// Blobs that could not be read this session (missing or unreadable);
  /// retried after [schedule] is called with `retryFailed`.
  final Set<String> _skipped = {};

  /// Whether extraction is in progress.
  bool get isIndexing => _running != null;

  /// Starts extracting any PDFs not yet indexed (no-op if running; a run
  /// in progress looks again when it finishes). Completes when idle.
  Future<void> schedule({bool retryFailed = false}) {
    if (_disposed) return Future.value();
    if (retryFailed) _skipped.clear();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _running = _run();
    notifyListeners();
    return run;
  }

  /// PDF blobs shown by live pages whose text has not been extracted.
  List<String> pendingBlobs() => [
    for (final row in _db.select('''
      SELECT DISTINCT blob FROM (
        SELECT CASE WHEN json_valid(background) AND json_extract(background, '\$.type') = 'pdf'
               THEN json_extract(background, '\$.blob') END AS blob
        FROM pages WHERE deleted = 0 AND background IS NOT NULL)
      WHERE blob IS NOT NULL AND blob NOT IN (SELECT blob FROM pdf_text_blobs)
      ORDER BY blob'''))
      if (row['blob'] case final String blob) blob,
  ];

  Future<void> _run() async {
    try {
      do {
        _again = false;
        for (final blob in pendingBlobs()) {
          if (_disposed) return;
          if (_skipped.contains(blob)) continue;
          if (!await _extract(blob)) _skipped.add(blob);
        }
      } while (_again && !_disposed);
    } finally {
      _running = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Extracts every page of [blob] not extracted yet. False if the blob is
  /// missing or unreadable.
  Future<bool> _extract(String blob) async {
    final Uint8List? bytes;
    try {
      bytes = await readBlob(blob);
    } on Exception {
      return false;
    }
    if (bytes == null || _disposed) return false;
    PdfTextDocument? doc;
    try {
      doc = await source.open(bytes);
      final done = {
        for (final r in _db.select('SELECT page FROM pdf_text WHERE blob = ?', [blob]))
          r['page'] as int,
      };
      final batch = <(int, String)>[];
      for (var i = 0; i < doc.pageCount; i++) {
        if (_disposed) return true;
        if (done.contains(i)) continue;
        batch.add((i, await doc.pageText(i)));
        if (batch.length >= batchSize) _write(blob, batch);
      }
      _write(blob, batch);
      _db.execute('INSERT OR REPLACE INTO pdf_text_blobs (blob, pages, ok) VALUES (?, ?, 1)', [
        blob,
        doc.pageCount,
      ]);
      return true;
    } on Object catch (e) {
      debugPrint('Cannot extract text of PDF $blob: $e');
      return false;
    } finally {
      await doc?.dispose();
    }
  }

  /// Stores and indexes a batch of page texts, then clears it.
  void _write(String blob, List<(int, String)> batch) {
    if (batch.isEmpty || _disposed) return;
    database.transaction(() {
      final insert = _db.prepare(
        'INSERT OR REPLACE INTO pdf_text (blob, page, text) VALUES (?, ?, ?)',
      );
      try {
        for (final (page, text) in batch) {
          insert.execute([blob, page, text.trim().isEmpty ? '' : text]);
        }
      } finally {
        insert.close();
      }
      SearchSchema.indexPdfPages(_db, blob, pdfPages: [for (final (page, _) in batch) page]);
    });
    batch.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

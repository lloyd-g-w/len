import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/waveform.dart';

/// What a stored file (blob) holds, told by its MIME type.
enum FileKind {
  pdf,
  image,
  audio,
  other;

  /// The kind of a blob stored as [mime] (recordings' waveforms count as
  /// audio: they belong to recordings).
  static FileKind of(String mime) {
    if (mime == 'application/pdf') return pdf;
    if (mime.startsWith('image/')) return image;
    if (mime.startsWith('audio/') || mime == Waveform.mime) return audio;
    return other;
  }
}

/// How much one notebook takes on this device: its ink and text, and the
/// files it shows that are here (each counted once).
class NotebookFootprint {
  const NotebookFootprint({
    required this.id,
    required this.title,
    required this.trashed,
    required this.bytes,
    required this.recordingBytes,
    required this.recordings,
  });

  final String id;
  final String title;

  /// Whether it is in the trash (it still takes its space).
  final bool trashed;

  /// Everything together, recordings included.
  final int bytes;

  /// Of [bytes], its recordings' audio here.
  final int recordingBytes;

  /// How many recordings it has (here or not).
  final int recordings;
}

/// What Len stores on this device, measured by [StorageQueries.survey].
class StorageSurvey {
  const StorageSurvey({
    required this.database,
    required this.files,
    required this.largest,
    required this.freeable,
    required this.freeableIds,
  });

  /// The database: handwriting, text, the library and the search index.
  final int database;

  /// Bytes of the files (PDFs, images, recordings) stored here, by kind.
  final Map<FileKind, int> files;

  /// The notebooks taking the most, largest first.
  final List<NotebookFootprint> largest;

  /// Bytes and ids of files the sync server holds whose copies here could
  /// go ([StorageQueries.freeable]), largest first.
  final int freeable;
  final List<String> freeableIds;

  /// Everything above together.
  int get total => database + files.values.fold(0, (a, b) => a + b);

  /// This survey with the database measured as [bytes] (natively the
  /// files, write-ahead log included).
  StorageSurvey withDatabase(int bytes) => StorageSurvey(
    database: bytes,
    files: files,
    largest: largest,
    freeable: freeable,
    freeableIds: freeableIds,
  );
}

/// Read-only measurements of what takes space (Settings → Storage, UX_AUDIT
/// R16-7). Plain SQL over [db], so it runs on any connection: natively on
/// a worker isolate's own (`platform/storage_survey`).
class StorageQueries {
  StorageQueries(this.db);

  final CommonDatabase db;

  /// Notebooks (by id) and the surfaces their ink and elements are on.
  static const _surfaces = '''
    surfaces(nb, sid) AS (
      SELECT id, id FROM notebooks WHERE deleted = 0
      UNION ALL SELECT notebook_id, id FROM pages WHERE deleted = 0)''';

  /// The blobs live rows reference, by notebook, with whether a recording
  /// holds them and whether the row is not yet synced (as
  /// `BlobReferences.all`, user templates aside): every string of a blob
  /// id's length in their JSON (malformed JSON: none).
  static final _refs =
      '''
    $_surfaces,
    refs(nb, sha, audio, dirty) AS (
      SELECT p.notebook_id, j.value, 0, p.dirty FROM pages p,
          json_tree(${_json('p.background')}) j
        WHERE p.deleted = 0 AND p.background IS NOT NULL AND j.type = 'text'
          AND length(j.value) = 64
      UNION ALL
      SELECT p.notebook_id, j.value, 0, p.dirty FROM pages p,
          json_tree(${_json('p.paper_data')}) j
        WHERE p.deleted = 0 AND p.paper_data <> '{}' AND j.type = 'text'
          AND length(j.value) = 64
      UNION ALL
      SELECT s.nb, j.value, 0, e.dirty FROM elements e JOIN surfaces s ON s.sid = e.surface_id,
          json_tree(${_json('e.data')}) j
        WHERE e.deleted = 0 AND j.type = 'text' AND length(j.value) = 64
      UNION ALL
      SELECT r.notebook_id, j.value, 1, r.dirty FROM recordings r, json_tree(${_json('r.audio')}) j
        WHERE r.deleted = 0 AND j.type = 'text' AND length(j.value) = 64
      UNION ALL
      SELECT notebook_id, waveform, 1, dirty FROM recordings WHERE deleted = 0 AND waveform <> '')''';

  static String _json(String column) =>
      "CASE WHEN json_valid($column) THEN $column ELSE 'null' END";

  /// Everything at once; [keep] are the notebooks whose files must stay
  /// (open in the editor), [largest] how many notebooks to list.
  StorageSurvey survey({Set<String> keep = const {}, int largest = 5}) {
    final freeable = this.freeable(keep: keep);
    return StorageSurvey(
      database: databaseBytes(),
      files: fileBytes(),
      largest: largestNotebooks(limit: largest),
      freeable: freeable.fold(0, (sum, b) => sum + b.size),
      freeableIds: [for (final b in freeable) b.sha],
    );
  }

  /// The database's size (its pages; natively the write-ahead log adds to it).
  int databaseBytes() {
    final count = db.select('PRAGMA page_count').first.columnAt(0) as int;
    final size = db.select('PRAGMA page_size').first.columnAt(0) as int;
    return count * size;
  }

  /// Bytes of the stored files by kind.
  Map<FileKind, int> fileBytes() {
    final bytes = {for (final kind in FileKind.values) kind: 0};
    for (final row in db.select('SELECT mime, SUM(size) AS s FROM blobs GROUP BY mime')) {
      final kind = FileKind.of(row['mime'] as String);
      bytes[kind] = bytes[kind]! + (row['s'] as int);
    }
    return bytes;
  }

  /// The [limit] notebooks taking the most here (none taking nothing),
  /// largest first: ink and elements (as stored, in bytes: `length` of
  /// text counts characters) plus the files they show that are here, each
  /// counted once per notebook.
  List<NotebookFootprint> largestNotebooks({int limit = 5}) {
    final content = <String, int>{
      for (final row in db.select('''
        WITH $_surfaces
        SELECT nb, SUM(b) AS b FROM (
          SELECT s.nb, length(st.points) + COALESCE(length(CAST(st.style AS BLOB)), 0) AS b
            FROM strokes st JOIN surfaces s ON s.sid = st.surface_id WHERE st.deleted = 0
          UNION ALL
          SELECT s.nb, length(CAST(e.data AS BLOB))
            FROM elements e JOIN surfaces s ON s.sid = e.surface_id WHERE e.deleted = 0)
        GROUP BY nb'''))
        row['nb'] as String: row['b'] as int,
    };
    final files = <String, (int, int)>{
      for (final row in db.select('''
        WITH $_refs
        SELECT r.nb, SUM(b.size) AS bytes, SUM(CASE WHEN r.audio THEN b.size ELSE 0 END) AS audio
        FROM (SELECT nb, sha, MAX(audio) AS audio FROM refs GROUP BY nb, sha) r
        JOIN blobs b ON b.sha256 = r.sha
        GROUP BY r.nb'''))
        row['nb'] as String: (row['bytes'] as int, row['audio'] as int),
    };
    final recordings = <String, int>{
      for (final row in db.select(
        'SELECT notebook_id, COUNT(*) AS c FROM recordings WHERE deleted = 0 GROUP BY notebook_id',
      ))
        row['notebook_id'] as String: row['c'] as int,
    };
    final all = [
      for (final row in db.select('SELECT id, title, trashed_at FROM notebooks WHERE deleted = 0'))
        if (row['id'] as String case final id when (content[id] ?? 0) + (files[id]?.$1 ?? 0) > 0)
          NotebookFootprint(
            id: id,
            title: row['title'] as String,
            trashed: row['trashed_at'] != null,
            bytes: (content[id] ?? 0) + (files[id]?.$1 ?? 0),
            recordingBytes: files[id]?.$2 ?? 0,
            recordings: recordings[id] ?? 0,
          ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    return all.take(limit).toList();
  }

  /// Files whose copies here could go, as they download again when shown:
  /// those the sync server holds (uploaded to it, not refused as too
  /// large) that live rows of pages, elements or recordings show. Never
  /// one a notebook in [keep] shows (open in the editor: it may be needed
  /// offline), one only rows not yet synced show (no server record keeps
  /// it from the server's clean-up yet), a user template (new pages copy
  /// it) or font, or a PDF whose text search has not read yet.
  List<({String sha, int size})> freeable({Set<String> keep = const {}}) => [
    for (final row in db.select(
      '''
      WITH $_refs
      SELECT b.sha256, b.size FROM blobs b
      WHERE b.uploaded = 1 AND b.rejected_limit IS NULL
        AND b.sha256 IN (SELECT sha FROM refs)
        AND b.sha256 NOT IN (SELECT sha FROM refs WHERE nb IN (SELECT value FROM json_each(?1)))
        AND b.sha256 NOT IN (SELECT sha FROM refs WHERE dirty)
        AND b.sha256 NOT IN (SELECT blob FROM templates WHERE deleted = 0)
        AND b.sha256 NOT IN (SELECT blob FROM fonts WHERE deleted = 0)
        AND b.sha256 NOT IN ($_unreadPdfs)
      ORDER BY b.size DESC''',
      [jsonEncode(keep.toList())],
    ))
      (sha: row['sha256'] as String, size: row['size'] as int),
  ];

  /// Blobs whose copies must stay here whatever the server holds: those
  /// the notebooks in [keep] show, rows not yet synced, user templates,
  /// user fonts and PDFs search has not read yet (as [freeable]; asked again right before copies go).
  Set<String> kept({Set<String> keep = const {}}) => {
    for (final row in db.select(
      '''
      WITH $_refs
      SELECT sha FROM refs WHERE nb IN (SELECT value FROM json_each(?1)) OR dirty
      UNION SELECT blob FROM templates WHERE deleted = 0
      UNION SELECT blob FROM fonts WHERE deleted = 0
      UNION $_unreadPdfs''',
      [jsonEncode(keep.toList())],
    ))
      row.columnAt(0) as String,
  };

  /// PDFs live pages show whose text search has not extracted (as
  /// `PdfTextIndexer.pendingBlobs`).
  static const _unreadPdfs = '''
    SELECT blob FROM (
      SELECT CASE WHEN json_valid(background) AND json_extract(background, '\$.type') = 'pdf'
             THEN json_extract(background, '\$.blob') END AS blob
      FROM pages WHERE deleted = 0 AND background IS NOT NULL)
    WHERE blob IS NOT NULL AND blob NOT IN (SELECT blob FROM pdf_text_blobs)''';
}

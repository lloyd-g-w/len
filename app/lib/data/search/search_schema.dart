import 'package:sqlite3/common.dart';

/// The local, derived full-text search index (never synced).
///
/// `search_docs` holds one row per searchable thing — a notebook title, a
/// folder name, a text box, or the text of an imported PDF page — and is
/// kept up to date by SQLite triggers on the synced tables, so local edits
/// and records applied by sync are indexed by the same write, whichever code
/// path made it. `search_fts` is an FTS5 index over it (external content);
/// where FTS5 is unavailable it is simply missing and queries fall back to
/// `LIKE` over `search_docs`.
///
/// PDF page text is extracted from the blobs off the UI thread
/// (`PdfTextIndexer`) into `pdf_text`, keyed by blob and page, so a PDF
/// imported into several notebooks is read once.
abstract final class SearchSchema {
  /// Document kinds stored in `search_docs.kind`.
  static const notebook = 'notebook';
  static const folder = 'folder';
  static const text = 'text';
  static const pdf = 'pdf';

  /// Creates (or completes) the index and fills it from the synced tables.
  /// Idempotent: safe however migrations from parallel branches end up
  /// ordered, and on databases where an earlier run lacked FTS5.
  static void create(CommonDatabase db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS search_docs (
        id         INTEGER PRIMARY KEY,
        kind       TEXT NOT NULL,
        ref_id     TEXT NOT NULL,
        surface_id TEXT NOT NULL,
        body       TEXT NOT NULL,
        UNIQUE (kind, ref_id)
      )''');
    db.execute('CREATE INDEX IF NOT EXISTS search_docs_by_surface ON search_docs(surface_id)');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pdf_text (
        blob TEXT NOT NULL,
        page INTEGER NOT NULL,
        text TEXT NOT NULL,
        PRIMARY KEY (blob, page)
      ) WITHOUT ROWID''');
    // One row per PDF blob whose text was extracted (or could not be).
    db.execute('''
      CREATE TABLE IF NOT EXISTS pdf_text_blobs (
        blob  TEXT PRIMARY KEY NOT NULL,
        pages INTEGER NOT NULL,
        ok    INTEGER NOT NULL
      ) WITHOUT ROWID''');
    _createSourceTriggers(db);
    ensureFts(db);
    rebuild(db);
  }

  /// Whether the FTS5 index exists on [db].
  static bool hasFts(CommonDatabase db) => db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'search_fts'")
      .isNotEmpty;

  /// Creates the FTS5 index and its sync triggers if FTS5 is available.
  /// Returns whether the index exists afterwards.
  static bool ensureFts(CommonDatabase db) {
    if (hasFts(db)) return true;
    try {
      // unicode61 folds case and (with remove_diacritics 2) accents;
      // prefix indexes make the per-term prefix queries cheap.
      db.execute('''
        CREATE VIRTUAL TABLE search_fts USING fts5(
          body, content = 'search_docs', content_rowid = 'id',
          tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3')''');
    } on SqliteException {
      return false; // Built without FTS5: queries use LIKE instead.
    }
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_docs_ai AFTER INSERT ON search_docs BEGIN
        INSERT INTO search_fts(rowid, body) VALUES (NEW.id, NEW.body);
      END''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_docs_ad AFTER DELETE ON search_docs BEGIN
        INSERT INTO search_fts(search_fts, rowid, body) VALUES ('delete', OLD.id, OLD.body);
      END''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_docs_au AFTER UPDATE ON search_docs BEGIN
        INSERT INTO search_fts(search_fts, rowid, body) VALUES ('delete', OLD.id, OLD.body);
        INSERT INTO search_fts(rowid, body) VALUES (NEW.id, NEW.body);
      END''');
    db.execute("INSERT INTO search_fts(search_fts) VALUES ('rebuild')");
    return true;
  }

  /// Empties the index and refills it from the synced tables (and the
  /// extracted PDF text).
  static void rebuild(CommonDatabase db) {
    db.execute('DELETE FROM search_docs');
    db.execute('''
      INSERT INTO search_docs (kind, ref_id, surface_id, body)
      SELECT '$notebook', id, id, title FROM notebooks WHERE deleted = 0''');
    db.execute('''
      INSERT INTO search_docs (kind, ref_id, surface_id, body)
      SELECT '$folder', id, id, name FROM folders WHERE deleted = 0''');
    db.execute('''
      INSERT INTO search_docs (kind, ref_id, surface_id, body)
      SELECT '$text', id, surface_id, ${_elementText()} FROM elements
      WHERE deleted = 0 AND type = 'text' AND ${_elementText()} <> ''
      ''');
    db.execute('''
      INSERT INTO search_docs (kind, ref_id, surface_id, body)
      SELECT '$pdf', p.id, p.id, t.text FROM pages p
      JOIN pdf_text t ON t.blob = ${_bgField('p.background', 'blob')}
                     AND t.page = ${_bgField('p.background', 'page')}
      WHERE p.deleted = 0 AND t.text <> ''
      ''');
    if (hasFts(db)) db.execute("INSERT INTO search_fts(search_fts) VALUES ('rebuild')");
  }

  /// Re-indexes the notebook pages showing PDF [blob] — only those showing
  /// one of [pdfPages] if given — after its text was extracted. One scan
  /// of `pages` per call.
  static void indexPdfPages(CommonDatabase db, String blob, {List<int>? pdfPages}) {
    final only = pdfPages == null
        ? ''
        : 'AND ${_bgField('background', 'page')} IN (${pdfPages.join(', ')})';
    final pages = '''
      SELECT id FROM pages WHERE background IS NOT NULL
        AND ${_bgField('background', 'blob')} = ? $only''';
    db.execute("DELETE FROM search_docs WHERE kind = '$pdf' AND ref_id IN ($pages)", [blob]);
    db.execute(
      '''
      INSERT INTO search_docs (kind, ref_id, surface_id, body)
      SELECT '$pdf', p.id, p.id, t.text FROM pages p
      JOIN pdf_text t ON t.blob = ? AND t.page = ${_bgField('p.background', 'page')}
      WHERE p.deleted = 0 AND p.id IN ($pages) AND t.text <> ''
      ''',
      [blob, blob],
    );
  }

  /// The trimmed text of an element's `data` JSON [column] ('' if none).
  static String _elementText([String column = 'data']) =>
      'CASE WHEN json_valid($column) '
      "THEN trim(coalesce(json_extract($column, '\$.text'), '')) ELSE '' END";

  /// A field of a page background JSON ([column]), NULL unless it is a PDF.
  static String _bgField(String column, String field) =>
      "CASE WHEN json_valid($column) AND json_extract($column, '\$.type') = 'pdf' "
      "THEN json_extract($column, '\$.$field') END";

  /// Triggers that mirror notebooks, folders, text elements and PDF pages
  /// into `search_docs`. Each only fires when an indexed column changes,
  /// so moves, recolours and sync bookkeeping (`dirty`) cost nothing.
  static void _createSourceTriggers(CommonDatabase db) {
    void mirror({
      required String name,
      required String table,
      required String kind,
      required String changed,
      required String insert,
    }) {
      final reindex =
          '''
        DELETE FROM search_docs WHERE kind = '$kind' AND ref_id = NEW.id;
        $insert;''';
      db.execute('''
        CREATE TRIGGER IF NOT EXISTS ${name}_ai AFTER INSERT ON $table BEGIN $reindex END''');
      db.execute('''
        CREATE TRIGGER IF NOT EXISTS ${name}_au AFTER UPDATE ON $table
        WHEN $changed BEGIN $reindex END''');
      db.execute('''
        CREATE TRIGGER IF NOT EXISTS ${name}_ad AFTER DELETE ON $table BEGIN
          DELETE FROM search_docs WHERE kind = '$kind' AND ref_id = OLD.id;
        END''');
    }

    mirror(
      name: 'search_notebooks',
      table: 'notebooks',
      kind: notebook,
      changed: 'OLD.title IS NOT NEW.title OR OLD.deleted IS NOT NEW.deleted',
      insert: '''
        INSERT INTO search_docs (kind, ref_id, surface_id, body)
        SELECT '$notebook', NEW.id, NEW.id, NEW.title WHERE NEW.deleted = 0''',
    );
    mirror(
      name: 'search_folders',
      table: 'folders',
      kind: folder,
      changed: 'OLD.name IS NOT NEW.name OR OLD.deleted IS NOT NEW.deleted',
      insert: '''
        INSERT INTO search_docs (kind, ref_id, surface_id, body)
        SELECT '$folder', NEW.id, NEW.id, NEW.name WHERE NEW.deleted = 0''',
    );
    final newText = _elementText('NEW.data');
    mirror(
      name: 'search_elements',
      table: 'elements',
      kind: text,
      changed:
          'OLD.data IS NOT NEW.data OR OLD.deleted IS NOT NEW.deleted '
          'OR OLD.surface_id IS NOT NEW.surface_id OR OLD.type IS NOT NEW.type',
      insert:
          '''
        INSERT INTO search_docs (kind, ref_id, surface_id, body)
        SELECT '$text', NEW.id, NEW.surface_id, $newText
        WHERE NEW.deleted = 0 AND NEW.type = 'text' AND $newText <> ''
      ''',
    );
    mirror(
      name: 'search_pages',
      table: 'pages',
      kind: pdf,
      changed: 'OLD.background IS NOT NEW.background OR OLD.deleted IS NOT NEW.deleted',
      insert:
          '''
        INSERT INTO search_docs (kind, ref_id, surface_id, body)
        SELECT '$pdf', NEW.id, NEW.id, t.text FROM pdf_text t
        WHERE NEW.deleted = 0 AND t.text <> ''
          AND t.blob = ${_bgField('NEW.background', 'blob')}
          AND t.page = ${_bgField('NEW.background', 'page')}''',
    );
  }
}

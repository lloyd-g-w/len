import '../../domain/notebook.dart';
import '../../domain/notebook_version.dart';
import '../../domain/paper.dart';
import '../blob_store.dart';
import '../page_rows.dart';
import '../record_fields.dart';
import '../syncable.dart';

/// How a [NotebookVersion]'s record is parsed (strictly: every field
/// required, docs/SYNC_PROTOCOL.md "Version history").
abstract final class VersionRows {
  /// The notebook settings a version keeps (record fields of `notebooks`).
  static const notebookFields = ['title', 'kind', 'paper', 'paperData', 'paperColor', 'coverColor'];

  /// The page fields a version keeps (record fields of `pages`).
  static const pageFields = [
    'width',
    'height',
    'paper',
    'paperData',
    'paperColor',
    'bookmarked',
    'background',
  ];

  /// Parses live record [record] (format 2, with `table`, or format 1,
  /// with `pages`, `canvas` and `blobs`); throws [FormatException] when
  /// malformed.
  static NotebookVersion fromRecord(SyncRecord record) {
    final f = RecordFields(record);
    String nonEmpty(String key) {
      final value = f.string(key);
      return value.isEmpty ? f.invalid(key) : value;
    }

    final notebookId = nonEmpty('notebookId');
    final notebook = _notebook(f, f.object('notebook'));
    final format2 = record.data!.containsKey('table');
    return NotebookVersion(
      id: record.id,
      notebookId: notebookId,
      createdAt: f.integer('createdAt'),
      kind: f.choice('kind', VersionKind.values),
      name: f.stringOrNull('name'),
      deviceId: nonEmpty('deviceId'),
      deviceName: f.string('deviceName'),
      notebook: notebook,
      table: format2 ? _shas(f, f.list('table'), 'table') : const [],
      inline: format2 ? null : _inline(f, notebookId),
      summary: _summary(f, f.object('summary')),
      size: f.integer('size'),
    );
  }

  /// The body a format 1 record carries.
  static VersionBody _inline(RecordFields f, String notebookId) {
    final canvasJson = f.objectOrNull('canvas');
    return VersionBody(
      pages: [
        for (final page in f.list('pages'))
          page is Map<String, Object?> ? _page(f, page, notebookId) : f.invalid('pages'),
      ],
      canvas: canvasJson == null ? null : _surface(f, canvasJson, 'canvas'),
      recordings: null,
      outline: null,
      blobs: _shas(f, f.list('blobs'), 'blobs'),
    );
  }

  /// The body in the rows of [version]'s table blobs (`VersionTable`):
  /// pages and the canvas checked as strictly as a record (throws
  /// [FormatException]), recordings and outline entries kept as they are
  /// (checked when written back), rows of other types ignored.
  static VersionBody bodyOf(NotebookVersion version, List<Map<String, Object?>> rows) {
    final f = RecordFields(
      SyncRecord(
        collection: 'versions',
        id: version.id,
        updatedAt: 0,
        deviceId: '-',
        deleted: false,
        data: const {},
      ),
    );
    final pages = <VersionPage>[];
    VersionSurface? canvas;
    final recordings = <VersionRecord>[];
    final outline = <VersionRecord>[];
    for (final row in rows) {
      final id = row['id'];
      if (id is! String || id.isEmpty) f.invalid('table');
      switch (row['t']) {
        case 'page':
          pages.add(_page(f, row, version.notebookId));
        case 'canvas':
          canvas = _surface(f, row, 'table');
        case 'recording':
          recordings.add((id: id, data: _data(f, row)));
        case 'outline':
          outline.add((id: id, data: _data(f, row)));
      }
    }
    if (version.isCanvas) canvas ??= VersionSurface.empty;
    return VersionBody(
      pages: version.isCanvas ? const [] : pages,
      canvas: version.isCanvas ? canvas : null,
      recordings: recordings,
      outline: outline,
    );
  }

  static Map<String, Object?> _data(RecordFields f, Map<String, Object?> row) =>
      switch (row['data']) {
        final Map<String, Object?> data => data,
        _ => f.invalid('table'),
      };

  static Map<String, Object?> _notebook(RecordFields f, Map<String, Object?> json) {
    final n = RecordFields(_nested(f, 'notebook', json));
    n.string('title');
    n.choice('kind', NotebookKind.values);
    final style = n.choice('paper', PaperStyle.values);
    if (style.needsParams || Paper.fromData(style, n.object('paperData')) == null) {
      f.invalid('notebook');
    }
    if (PaperColor.tryParse(n.string('paperColor')) == null) f.invalid('notebook');
    n.integer('coverColor');
    return {for (final key in notebookFields) key: json[key]};
  }

  static VersionPage _page(RecordFields f, Map<String, Object?> json, String notebookId) {
    final id = json['id'];
    if (id is! String || id.isEmpty) f.invalid('pages');
    final fields = {
      for (final key in pageFields)
        if (json.containsKey(key)) key: json[key] else key: f.invalid('pages'),
    };
    // Checked as a page record would be.
    PageRows.fromRecord(
      SyncRecord(
        collection: 'pages',
        id: id,
        updatedAt: 0,
        deviceId: '-',
        deleted: false,
        data: {...fields, 'notebookId': notebookId, 'sortKey': 0},
      ),
    );
    return VersionPage(id: id, fields: fields, content: _surface(f, json, 'pages'));
  }

  /// A surface: `ink` and `items` (packs); in table rows also `blobs`
  /// and `text` (a `recognised_text` record's data, or null).
  static VersionSurface _surface(RecordFields f, Map<String, Object?> json, String key) {
    final ink = json['ink'];
    final items = json['items'];
    if (ink is! List<Object?> || items is! List<Object?>) f.invalid(key);
    final table = json.containsKey('t');
    final blobs = table ? json['blobs'] : const <Object?>[];
    final text = table ? json['text'] : null;
    if (blobs is! List<Object?>) f.invalid(key);
    if (text is! Map<String, Object?>? || (table && !json.containsKey('text'))) f.invalid(key);
    return VersionSurface(
      ink: _shas(f, ink, key),
      items: _shas(f, items, key),
      blobs: _shas(f, blobs, key),
      text: text,
    );
  }

  static List<String> _shas(RecordFields f, List<Object?> list, String key) => [
    for (final sha in list)
      if (sha is String && BlobStore.isValidId(sha)) sha else f.invalid(key),
  ];

  static VersionSummary _summary(RecordFields f, Map<String, Object?> json) {
    final s = RecordFields(_nested(f, 'summary', json));
    return VersionSummary(
      pages: s.integer('pages'),
      strokes: s.integer('strokes'),
      pagesAdded: s.integer('pagesAdded'),
      pagesRemoved: s.integer('pagesRemoved'),
      pagesEdited: s.integer('pagesEdited'),
      strokesAdded: s.integer('strokesAdded'),
      strokesRemoved: s.integer('strokesRemoved'),
      focus: s.stringOrNull('focus'),
    );
  }

  /// A record over a nested object, so its fields are read as strictly.
  static SyncRecord _nested(RecordFields f, String key, Map<String, Object?> json) => SyncRecord(
    collection: f.record.collection,
    id: '${f.record.id}.$key',
    updatedAt: 0,
    deviceId: '-',
    deleted: false,
    data: json,
  );
}

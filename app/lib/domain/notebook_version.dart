import 'dart:convert';

/// How a version came to be (docs/SYNC_PROTOCOL.md, "Version history").
enum VersionKind {
  /// Made after a stretch of editing; thinned over time.
  auto,

  /// Saved by hand ("Save version…"); kept until deleted.
  named,

  /// The state just before a restore, so the restore can be undone.
  restore;

  /// Whether thinning and the storage budget may remove it.
  bool get thinned => this != named;
}

/// What a surface held in a version: the packs (content-addressed blobs) of
/// its live strokes ([ink]) and of its live elements ([items]), in order,
/// the blobs those elements show ([blobs]: images) and the handwriting
/// recognised on it ([text], a `recognised_text` record's data; null: none
/// or not kept).
class VersionSurface {
  const VersionSurface({required this.ink, required this.items, this.blobs = const [], this.text});

  static const empty = VersionSurface(ink: [], items: []);

  final List<String> ink;
  final List<String> items;
  final List<String> blobs;
  final Map<String, Object?>? text;

  /// Every pack.
  Iterable<String> get packs => [...ink, ...items];

  Map<String, Object?> toJson() => {'ink': ink, 'items': items, 'blobs': blobs, 'text': text};

  @override
  bool operator ==(Object other) =>
      other is VersionSurface &&
      _same(other.ink, ink) &&
      _same(other.items, items) &&
      _same(other.blobs, blobs) &&
      jsonEncode(other.text) == jsonEncode(text);

  @override
  int get hashCode => Object.hash(Object.hashAll(ink), Object.hashAll(items));

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A page as a version holds it: its id, its `pages` record fields (without
/// `notebookId` and `sortKey`: its place is its index) and its content.
class VersionPage {
  const VersionPage({required this.id, required this.fields, required this.content});

  final String id;

  /// `width, height, paper, paperData, paperColor, bookmarked, background`.
  final Map<String, Object?> fields;

  final VersionSurface content;

  /// Whether [other] holds the same page (fields and content).
  bool sameAs(VersionPage other) =>
      other.id == id && other.content == content && jsonEncode(other.fields) == jsonEncode(fields);
}

/// A record a version keeps whole (a recording, an outline entry): its id
/// and its record `data` without `notebookId`.
typedef VersionRecord = ({String id, Map<String, Object?> data});

/// What a version holds besides its notebook's settings: its pages (or
/// canvas), recordings and outline. Versions record it in table blobs
/// (docs/SYNC_PROTOCOL.md, "Version history"), read with
/// `VersionContent.body`; versions written before (format 1) carried it
/// in the record, without recordings, outline or recognised text.
class VersionBody {
  const VersionBody({
    required this.pages,
    required this.canvas,
    required this.recordings,
    required this.outline,
    this.blobs = const [],
  });

  /// Its pages in order (empty for a canvas).
  final List<VersionPage> pages;

  /// A canvas notebook's surface; null for a paged one.
  final VersionSurface? canvas;

  /// Its recordings and outline entries; null when not kept (format 1).
  final List<VersionRecord>? recordings;
  final List<VersionRecord>? outline;

  /// Format 1: the blobs the packs' items reference (images), kept in the
  /// record (format 2 keeps them per surface).
  final List<String> blobs;

  /// Every pack it references.
  Set<String> get packs => {for (final p in pages) ...p.content.packs, ...?canvas?.packs};

  /// Its page [id], if it holds it.
  VersionPage? page(String id) => pages.where((p) => p.id == id).firstOrNull;
}

/// What changed since the version before (counts; [focus] the first page
/// changed, which the timeline shows).
class VersionSummary {
  const VersionSummary({
    required this.pages,
    required this.strokes,
    this.pagesAdded = 0,
    this.pagesRemoved = 0,
    this.pagesEdited = 0,
    this.strokesAdded = 0,
    this.strokesRemoved = 0,
    this.focus,
  });

  /// Pages and strokes in the version.
  final int pages;
  final int strokes;
  final int pagesAdded;
  final int pagesRemoved;
  final int pagesEdited;
  final int strokesAdded;
  final int strokesRemoved;
  final String? focus;

  Map<String, Object?> toJson() => {
    'pages': pages,
    'strokes': strokes,
    'pagesAdded': pagesAdded,
    'pagesRemoved': pagesRemoved,
    'pagesEdited': pagesEdited,
    'strokesAdded': strokesAdded,
    'strokesRemoved': strokesRemoved,
    'focus': focus,
  };
}

/// One saved state of a notebook (a synced `versions` record).
class NotebookVersion {
  const NotebookVersion({
    required this.id,
    required this.notebookId,
    required this.createdAt,
    required this.kind,
    required this.name,
    required this.deviceId,
    required this.deviceName,
    required this.notebook,
    required this.table,
    required this.summary,
    required this.size,
    this.inline,
  });

  final String id;
  final String notebookId;

  /// When it was made (ms since epoch).
  final int createdAt;
  final VersionKind kind;

  /// The user's name for it, if any.
  final String? name;

  /// The device that made it, and how it calls itself (`Android`).
  final String deviceId;
  final String deviceName;

  /// The notebook's settings: `title, kind, paper, paperData, paperColor,
  /// coverColor` as on its record.
  final Map<String, Object?> notebook;

  /// The table blobs holding its [VersionBody], in order (empty for a
  /// version of format 1, whose body is [inline]).
  final List<String> table;

  /// The body a version of format 1 carried in its record.
  final VersionBody? inline;

  final VersionSummary summary;

  /// Bytes of the packs and table blobs this version added.
  final int size;

  /// The notebook's title then.
  String get title => notebook['title'] as String? ?? '';

  /// Whether it is a version of a canvas notebook.
  bool get isCanvas => notebook['kind'] == 'canvas';

  /// A key equal for versions holding the same content and settings (table
  /// blobs are content-addressed).
  String get contentKey => jsonEncode({
    'notebook': notebook,
    'table': table,
    if (inline case final body?)
      'inline': [
        for (final p in body.pages) [p.id, p.fields, p.content.toJson()],
        body.canvas?.toJson(),
      ],
  });

  NotebookVersion copyWith({String? name, bool clearName = false}) => NotebookVersion(
    id: id,
    notebookId: notebookId,
    createdAt: createdAt,
    kind: kind,
    name: clearName ? null : name ?? this.name,
    deviceId: deviceId,
    deviceName: deviceName,
    notebook: notebook,
    table: table,
    inline: inline,
    summary: summary,
    size: size,
  );

  /// The record data (docs/SYNC_PROTOCOL.md): format 2, or format 1 for a
  /// version read in it (renamed: kept as it was).
  Map<String, Object?> toData() => {
    'notebookId': notebookId,
    'createdAt': createdAt,
    'kind': kind.name,
    'name': name,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'notebook': notebook,
    if (inline case final body?) ...{
      'pages': [
        for (final p in body.pages)
          {'id': p.id, ...p.fields, 'ink': p.content.ink, 'items': p.content.items},
      ],
      'canvas': switch (body.canvas) {
        final c? => {'ink': c.ink, 'items': c.items},
        null => null,
      },
      'blobs': body.blobs,
    } else
      'table': table,
    'summary': summary.toJson(),
    'size': size,
  };
}

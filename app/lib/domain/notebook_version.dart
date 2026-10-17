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
/// its live strokes ([ink]) and of its live elements ([items]), in order.
class VersionSurface {
  const VersionSurface({required this.ink, required this.items});

  static const empty = VersionSurface(ink: [], items: []);

  final List<String> ink;
  final List<String> items;

  /// Every pack.
  Iterable<String> get packs => [...ink, ...items];

  Map<String, Object?> toJson() => {'ink': ink, 'items': items};

  @override
  bool operator ==(Object other) =>
      other is VersionSurface && _same(other.ink, ink) && _same(other.items, items);

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

  Map<String, Object?> toJson() => {'id': id, ...fields, ...content.toJson()};

  /// Whether [other] holds the same page (fields and content).
  bool sameAs(VersionPage other) =>
      other.id == id && other.content == content && jsonEncode(other.fields) == jsonEncode(fields);
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
    required this.pages,
    required this.canvas,
    required this.blobs,
    required this.summary,
    required this.size,
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

  /// Its pages in order (empty for a canvas).
  final List<VersionPage> pages;

  /// A canvas notebook's surface; null for a paged one.
  final VersionSurface? canvas;

  /// Blobs the packs' items reference (images).
  final List<String> blobs;

  final VersionSummary summary;

  /// Bytes of the packs this version added.
  final int size;

  /// The notebook's title then.
  String get title => notebook['title'] as String? ?? '';

  /// Every pack it references.
  Set<String> get packs => {for (final p in pages) ...p.content.packs, ...?canvas?.packs};

  /// A key equal for versions holding the same content and settings.
  String get contentKey => jsonEncode({
    'notebook': notebook,
    'pages': [for (final p in pages) p.toJson()],
    'canvas': canvas?.toJson(),
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
    pages: pages,
    canvas: canvas,
    blobs: blobs,
    summary: summary,
    size: size,
  );

  /// The record data (docs/SYNC_PROTOCOL.md).
  Map<String, Object?> toData() => {
    'notebookId': notebookId,
    'createdAt': createdAt,
    'kind': kind.name,
    'name': name,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'notebook': notebook,
    'pages': [for (final p in pages) p.toJson()],
    'canvas': canvas?.toJson(),
    'blobs': blobs,
    'summary': summary.toJson(),
    'size': size,
  };
}

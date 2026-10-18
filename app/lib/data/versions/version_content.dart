import 'dart:typed_data';

import '../../domain/notebook.dart';
import '../../domain/notebook_page.dart';
import '../../domain/notebook_version.dart';
import '../../domain/paper.dart';
import '../../domain/shape_ids.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../blob_links.dart';
import '../blob_references.dart';
import '../blob_store.dart';
import '../element_repository.dart';
import '../page_rows.dart';
import '../stroke_row.dart';
import '../syncable.dart';
import 'version_packs.dart';
import 'version_rows.dart';
import 'version_table.dart';
import 'work_slices.dart';

/// A surface as a version holds it.
typedef SurfaceContent = ({List<Stroke> strokes, List<SurfaceElement> elements});

/// Thrown when a version's content is neither on this device nor to be
/// fetched (offline, or the server lacks it).
class VersionUnavailable implements Exception {
  const VersionUnavailable(this.missing);

  /// How many packs are missing.
  final int missing;

  @override
  String toString() => 'VersionUnavailable($missing packs missing)';
}

/// Reads what versions hold: their pages, and their surfaces' strokes and
/// elements from the packs (fetched first when not on this device).
class VersionContent {
  VersionContent({required this.blobs, this.fetch, this.links});

  final BlobStore blobs;

  /// Where the blobs a table blob names are noted when it is read here.
  final BlobLinks? links;

  /// Bodies read, by version id, most recently used last.
  final Map<String, VersionBody> _bodies = {};
  static const _cachedBodies = 16;

  /// Fetches blob [sha] from the sync server; true once it is here. Null:
  /// no server.
  final Future<bool> Function(String sha)? fetch;

  /// Decoded packs, most recently used last.
  final Map<String, List<PackItem>> _packs = {};
  static const _cachedPacks = 128;

  /// Decoded table blobs, most recently used last: versions next to each
  /// other share all but one or two (the history's thumbnails read many).
  final Map<String, List<Map<String, Object?>>> _tables = {};
  static const _cachedTables = 256;

  /// The strokes of packs as a surface's (`surfaceId:sha`), most recently
  /// used last, kept up to [_cachedStrokes] strokes: the versions of a
  /// canvas share almost all of their packs, so their thumbnails share the
  /// strokes too instead of decoding the canvas again for each.
  final Map<String, List<Stroke>> _strokes = {};
  var _strokesKept = 0;
  static const _cachedStrokes = 100000;

  /// [page] of [version] as a page of its notebook (a version's pages are
  /// valid: they were checked when the record was read).
  static NotebookPage pageOf(NotebookVersion version, VersionPage page, {double sortKey = 0}) =>
      PageRows.fromRecord(
        SyncRecord(
          collection: 'pages',
          id: page.id,
          updatedAt: 0,
          deviceId: '-',
          deleted: false,
          data: {...page.fields, 'notebookId': version.notebookId, 'sortKey': sortKey},
        ),
      );

  /// The notebook's settings in [version] applied to [notebook].
  static Notebook settingsOn(Notebook notebook, NotebookVersion version) {
    final n = version.notebook;
    final paper = Paper.fromData(
      PaperStyle.parse(n['paper'] as String),
      n['paperData'] as Map<String, Object?>,
    );
    return notebook.copyWith(
      title: n['title'] as String,
      paper: paper ?? notebook.paper,
      paperColor: PaperColor.parse(n['paperColor'] as String?),
      coverColor: n['coverColor'] as int,
    );
  }

  /// The body of [version]: in its record (format 1), else read from its
  /// table blobs (fetched when not here). Throws [VersionUnavailable] when
  /// some can't be had or are malformed.
  Future<VersionBody> body(NotebookVersion version) async {
    if (version.inline case final body?) return body;
    if (_bodies.remove(version.id) case final body?) return _bodies[version.id] = body;
    final rows = <Map<String, Object?>>[];
    var missing = 0;
    final slices = WorkSlices();
    for (final sha in version.table) {
      await slices.yieldIfDue();
      final run = await _tableRows(sha);
      if (run == null) {
        missing++;
      } else {
        rows.addAll(run);
      }
    }
    if (missing > 0) throw VersionUnavailable(missing);
    final VersionBody body;
    try {
      body = VersionRows.bodyOf(version, rows);
    } on FormatException {
      throw VersionUnavailable(version.table.length);
    }
    remember(version, body);
    return body;
  }

  /// Keeps [body] as [version]'s (one made here).
  void remember(NotebookVersion version, VersionBody body) {
    _bodies[version.id] = body;
    if (_bodies.length > _cachedBodies) _bodies.remove(_bodies.keys.first);
  }

  /// The rows of table blob [sha] (fetched if not here), noting the blobs
  /// they name; null when it can't be had or is no table blob.
  Future<List<Map<String, Object?>>?> _tableRows(String sha) async {
    if (_tables.remove(sha) case final rows?) return _tables[sha] = rows;
    var bytes = await blobs.read(sha);
    if (bytes == null && (await fetch?.call(sha) ?? false)) bytes = await blobs.read(sha);
    if (bytes == null) return null;
    final rows = VersionTable.decode(Uint8List.fromList(bytes));
    if (rows != null && links != null && !links!.knows(sha)) {
      links!.add(sha, BlobReferences.inValue(rows));
    }
    if (rows != null) {
      _tables[sha] = rows;
      if (_tables.length > _cachedTables) _tables.remove(_tables.keys.first);
    }
    return rows;
  }

  /// Whether every pack of [surfaces] is on this device.
  bool isHere(Iterable<VersionSurface> surfaces) =>
      surfaces.every((s) => s.packs.every((sha) => blobs.sizeOf(sha) != null));

  /// Makes sure every pack of [surfaces] is here, fetching those that are
  /// not; throws [VersionUnavailable] if some cannot be had.
  Future<void> ensure(Iterable<VersionSurface> surfaces) async {
    var missing = 0;
    // A canvas has thousands of packs: looked up in slices.
    final slices = WorkSlices();
    for (final sha in {for (final s in surfaces) ...s.packs}) {
      await slices.yieldIfDue();
      if (await blobs.has(sha)) continue;
      if (!(await fetch?.call(sha) ?? false)) missing++;
    }
    if (missing > 0) throw VersionUnavailable(missing);
  }

  /// The strokes and elements of [surface] as surface [surfaceId]: packs
  /// not here (and not to be fetched) or items that are malformed are left
  /// out, unless [strict], which throws [VersionUnavailable] instead.
  ///
  /// With [renamed] (old id → new id: the notebook, pages, strokes and
  /// elements of a copy), items take their new ids, and so do the
  /// references among them: links to pages, text flows, and shapes with
  /// their connectors ([ShapeIds]; names no item has get ids from [newId]).
  Future<SurfaceContent> load(
    VersionSurface surface,
    String surfaceId, {
    bool strict = false,
    Map<String, String>? renamed,
    String Function()? newId,
  }) async {
    final strokes = <Stroke>[];
    final elements = <SurfaceElement>[];
    String rename(String id) => renamed?[id] ?? id;
    final shapeIdOf = renamed == null ? null : ShapeIds.mapper(renamed, newId ?? () => '');
    final slices = WorkSlices();
    if (renamed == null) {
      for (final sha in surface.ink) {
        await slices.yieldIfDue();
        strokes.addAll(await _strokesOf(sha, surfaceId, strict: strict, slices: slices));
      }
    } else {
      for (final (id, data) in await _itemsOf(surface.ink, strict: strict, slices: slices)) {
        await slices.yieldIfDue();
        try {
          final style = shapeIdOf == null ? null : ShapeIds.remapStyle(data['style'], shapeIdOf);
          final record = style == null ? data : {...data, 'style': style};
          strokes.add(StrokeRow.strokeFromRecord(rename(id), {...record, 'surfaceId': surfaceId}));
        } on FormatException {
          // Left out (docs/SYNC_PROTOCOL.md, "Version history").
        }
      }
    }
    for (final (id, data) in await _itemsOf(surface.items, strict: strict, slices: slices)) {
      try {
        elements.add(
          ElementRepository.elementFromRecord(
            SyncRecord(
              collection: 'elements',
              id: rename(id),
              updatedAt: 0,
              deviceId: '-',
              deleted: false,
              data: {
                ...data,
                'surfaceId': surfaceId,
                if (renamed != null && data['data'] is Map<String, Object?>)
                  'data': _renamedElementData(data['data']! as Map<String, Object?>, rename),
              },
            ),
          ),
        );
      } on FormatException {
        // As above.
      } on TypeError {
        // As above.
      }
    }
    return (strokes: strokes, elements: elements);
  }

  /// The stroke ids in [surface]'s packs that are here.
  Future<Set<String>> strokeIds(VersionSurface surface) async => {
    for (final (id, _) in await _itemsOf(surface.ink, strict: false)) id,
  };

  /// The stroke and element ids in [surface]'s packs that are here.
  Future<Set<String>> itemIds(VersionSurface surface) async => {
    for (final (id, _) in await _itemsOf(surface.packs.toList(), strict: false)) id,
  };

  /// Element [data] with the ids it refers to renamed: a link's page (and
  /// notebook), a text flow's box before (a flow from a box not in the
  /// copy is dropped: the box stands alone).
  static Map<String, Object?> _renamedElementData(
    Map<String, Object?> data,
    String Function(String) rename,
  ) => {
    for (final MapEntry(:key, :value) in data.entries)
      if (key != 'flow') key: value,
    if (data['target'] case {'notebook': final String notebook, 'page': final String page})
      'target': {
        ...data['target']! as Map<String, Object?>,
        'notebook': rename(notebook),
        'page': rename(page),
      },
    if (data['flow'] case {'from': final String from} when rename(from) != from)
      'flow': {...data['flow']! as Map<String, Object?>, 'from': rename(from)},
  };

  /// The strokes of pack [sha] as surface [surfaceId]'s (from the cache;
  /// none when the pack can't be had, unless [strict]).
  Future<List<Stroke>> _strokesOf(
    String sha,
    String surfaceId, {
    required bool strict,
    required WorkSlices slices,
  }) async {
    final key = '$surfaceId:$sha';
    if (_strokes.remove(key) case final strokes?) return _strokes[key] = strokes;
    final items = await _pack(sha);
    if (items == null) {
      if (strict) throw const VersionUnavailable(1);
      return const [];
    }
    final strokes = <Stroke>[];
    for (final (id, data) in items) {
      try {
        strokes.add(StrokeRow.strokeFromRecord(id, {...data, 'surfaceId': surfaceId}));
      } on FormatException {
        // Left out (docs/SYNC_PROTOCOL.md, "Version history").
      }
    }
    _strokes[key] = strokes;
    _strokesKept += strokes.length;
    while (_strokesKept > _cachedStrokes && _strokes.length > 1) {
      final oldest = _strokes.keys.first;
      _strokesKept -= _strokes.remove(oldest)!.length;
    }
    return strokes;
  }

  Future<List<PackItem>> _itemsOf(
    List<String> packs, {
    required bool strict,
    WorkSlices? slices,
  }) async {
    final items = <PackItem>[];
    for (final sha in packs) {
      await slices?.yieldIfDue();
      final pack = await _pack(sha);
      if (pack == null && strict) throw const VersionUnavailable(1);
      items.addAll(pack ?? const []);
    }
    return items;
  }

  Future<List<PackItem>?> _pack(String sha) async {
    if (_packs.remove(sha) case final items?) return _packs[sha] = items;
    var bytes = await blobs.read(sha);
    if (bytes == null && (await fetch?.call(sha) ?? false)) bytes = await blobs.read(sha);
    final items = bytes == null ? null : VersionPacks.decode(Uint8List.fromList(bytes));
    if (items == null) return null;
    _packs[sha] = items;
    if (_packs.length > _cachedPacks) _packs.remove(_packs.keys.first);
    return items;
  }
}

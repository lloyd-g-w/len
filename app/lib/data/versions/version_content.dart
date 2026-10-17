import 'dart:typed_data';

import '../../domain/notebook.dart';
import '../../domain/notebook_page.dart';
import '../../domain/notebook_version.dart';
import '../../domain/paper.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../blob_store.dart';
import '../element_repository.dart';
import '../page_rows.dart';
import '../stroke_row.dart';
import '../syncable.dart';
import 'version_packs.dart';

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
  VersionContent({required this.blobs, this.fetch});

  final BlobStore blobs;

  /// Fetches blob [sha] from the sync server; true once it is here. Null:
  /// no server.
  final Future<bool> Function(String sha)? fetch;

  /// Decoded packs, most recently used last.
  final Map<String, List<PackItem>> _packs = {};
  static const _cachedPacks = 128;

  /// The pages of [version] as pages of its notebook (sort keys 0, 1, …).
  static List<NotebookPage> pagesOf(NotebookVersion version) => [
    for (final (i, page) in version.pages.indexed) pageOf(version, page, sortKey: i.toDouble()),
  ];

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

  /// Whether every pack of [surfaces] is on this device.
  bool isHere(Iterable<VersionSurface> surfaces) =>
      surfaces.every((s) => s.packs.every((sha) => blobs.sizeOf(sha) != null));

  /// Makes sure every pack of [surfaces] is here, fetching those that are
  /// not; throws [VersionUnavailable] if some cannot be had.
  Future<void> ensure(Iterable<VersionSurface> surfaces) async {
    var missing = 0;
    for (final sha in {for (final s in surfaces) ...s.packs}) {
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
  /// references among them: links to pages, text flows, connectors.
  Future<SurfaceContent> load(
    VersionSurface surface,
    String surfaceId, {
    bool strict = false,
    Map<String, String>? renamed,
  }) async {
    final strokes = <Stroke>[];
    final elements = <SurfaceElement>[];
    String rename(String id) => renamed?[id] ?? id;
    for (final (id, data) in await _itemsOf(surface.ink, strict: strict)) {
      try {
        final record = renamed == null ? data : _renamedStroke(data, rename);
        strokes.add(StrokeRow.strokeFromRecord(rename(id), {...record, 'surfaceId': surfaceId}));
      } on FormatException {
        // Left out (docs/SYNC_PROTOCOL.md, "Version history").
      }
    }
    for (final (id, data) in await _itemsOf(surface.items, strict: strict)) {
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

  /// Stroke record [data] with its connectors' ends (`style.sh.a`) renamed.
  static Map<String, Object?> _renamedStroke(
    Map<String, Object?> data,
    String Function(String) rename,
  ) {
    final style = data['style'];
    if (style is! Map<String, Object?>) return data;
    final shape = style['sh'];
    if (shape is! Map<String, Object?>) return data;
    final ends = shape['a'];
    if (ends is! List<Object?>) return data;
    return {
      ...data,
      'style': {
        ...style,
        'sh': {
          ...shape,
          'a': [
            for (final end in ends)
              if (end case {'id': final String id})
                {...end as Map<String, Object?>, 'id': rename(id)}
              else
                end,
          ],
        },
      },
    };
  }

  /// Element [data] with the ids it refers to renamed: a link's page (and
  /// notebook), a text flow's box before.
  static Map<String, Object?> _renamedElementData(
    Map<String, Object?> data,
    String Function(String) rename,
  ) => {
    ...data,
    if (data['target'] case {'notebook': final String notebook, 'page': final String page})
      'target': {
        ...data['target']! as Map<String, Object?>,
        'notebook': rename(notebook),
        'page': rename(page),
      },
    if (data['flow'] case {'from': final String from})
      'flow': {...data['flow']! as Map<String, Object?>, 'from': rename(from)},
  };

  Future<List<PackItem>> _itemsOf(List<String> packs, {required bool strict}) async {
    final items = <PackItem>[];
    for (final sha in packs) {
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

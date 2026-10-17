import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';

import '../../domain/notebook.dart';
import '../../domain/notebook_version.dart';
import '../blob_references.dart';
import '../blob_store.dart';
import '../notebook_rows.dart';
import '../page_rows.dart';
import '../repositories.dart';
import '../syncable_table.dart';
import 'version_content.dart';
import 'version_packs.dart';
import 'version_rows.dart';
import 'version_table.dart';
import 'work_slices.dart';

/// A surface packed: its packs, the blobs its elements show and how many
/// strokes it holds.
typedef PackedSurface = ({VersionSurface surface, List<String> blobs, int strokes});

/// Makes versions of notebooks from what is stored now (docs/ARCHITECTURE.md,
/// "Version history"): every surface packed (or its packs taken from the
/// `version_packs` cache while its change mark holds), with its recognised
/// handwriting, the recordings and the outline, written as table blobs;
/// the summary against the newest version before.
class VersionSnapshots {
  VersionSnapshots({
    required this.repositories,
    required this.blobs,
    required this.content,
    required this.deviceName,
  });

  final Repositories repositories;
  final BlobStore blobs;

  /// Reads versions' bodies (the one before, for the summary) and keeps
  /// the body of a version made here.
  final VersionContent content;

  /// How this device names itself (`Android`).
  final String deviceName;

  CommonDatabase get _db => repositories.versions.db;

  /// Makes a version of notebook [notebookId] now and saves it; returns it,
  /// or null when the notebook is gone or (unless [force]) nothing changed
  /// since its newest version.
  Future<NotebookVersion?> take(
    String notebookId, {
    VersionKind kind = VersionKind.auto,
    String? name,
    bool force = false,
  }) async {
    final made = await build(notebookId, kind: kind, name: name);
    if (made == null) return null;
    final previous = repositories.versions.latest(notebookId);
    if (!force && previous != null && previous.contentKey == made.contentKey) return null;
    repositories.versions.save(made);
    return made;
  }

  /// The version [take] would save (not saved).
  Future<NotebookVersion?> build(
    String notebookId, {
    VersionKind kind = VersionKind.auto,
    String? name,
  }) async {
    final versions = repositories.versions;
    final rows = _db.select('SELECT * FROM notebooks WHERE id = ? AND deleted = 0', [notebookId]);
    if (rows.isEmpty) return null;
    final notebookData = NotebookRows.recordData(rows.first);
    final notebook = {for (final key in VersionRows.notebookFields) key: notebookData[key]};
    final canvas = notebook['kind'] == NotebookKind.canvas.name;
    final pageRows = canvas
        ? const <Row>[]
        : _db.select(
            'SELECT * FROM pages WHERE notebook_id = ? AND deleted = 0 ORDER BY sort_key, id',
            [notebookId],
          );
    final previous = versions.latest(notebookId);
    var strokes = 0;
    final pages = <VersionPage>[];
    VersionSurface? canvasSurface;
    final counts = <String, int>{};
    final slices = WorkSlices();
    for (final row in pageRows) {
      await slices.yieldIfDue();
      final id = row['id'] as String;
      final data = PageRows.recordData(row);
      final packed = await pack(id);
      strokes += counts[id] = packed.strokes;
      pages.add(
        VersionPage(
          id: id,
          fields: {for (final key in VersionRows.pageFields) key: data[key]},
          content: _withText(packed, id),
        ),
      );
    }
    if (canvas) {
      final packed = await pack(notebookId);
      strokes = counts[notebookId] = packed.strokes;
      canvasSurface = _withText(packed, notebookId);
    }
    final body = VersionBody(
      pages: pages,
      canvas: canvasSurface,
      recordings: _records(
        repositories.recordings,
        'SELECT * FROM recordings WHERE notebook_id = ? AND deleted = 0 ORDER BY started_at, id',
        notebookId,
      ),
      outline: _records(
        repositories.outline,
        'SELECT * FROM outline WHERE notebook_id = ? AND deleted = 0 ORDER BY created_at, id',
        notebookId,
      ),
    );
    final table = await _putTable(VersionTable.rowsOf(body, notebookId), slices);
    final made = NotebookVersion(
      id: versions.clock.newId(),
      notebookId: notebookId,
      createdAt: versions.clock.nowMs(),
      kind: kind,
      name: name,
      deviceId: versions.deviceId,
      deviceName: deviceName,
      notebook: notebook,
      table: table,
      summary: VersionSummary(pages: pages.length, strokes: strokes),
      size: 0,
    );
    content.remember(made, body);
    VersionBody? before;
    if (previous != null) {
      try {
        before = await content.body(previous);
      } on VersionUnavailable {
        before = null; // Counted as if it were the first.
      }
    }
    final old = {...?before?.packs, ...?previous?.table};
    final size = {
      ...body.packs,
      ...table,
    }.difference(old).fold(0, (sum, sha) => sum + (blobs.sizeOf(sha) ?? 0));
    return _withSummary(made, body, before, size, counts);
  }

  /// [packed] with the handwriting recognised on [surfaceId].
  VersionSurface _withText(PackedSurface packed, String surfaceId) {
    final rows = _db.select('SELECT * FROM recognised_text WHERE id = ? AND deleted = 0', [
      surfaceId,
    ]);
    return VersionSurface(
      ink: packed.surface.ink,
      items: packed.surface.items,
      blobs: packed.blobs,
      text: rows.isEmpty ? null : repositories.recognisedText.rowToRecord(rows.first).data,
    );
  }

  /// The live records [sql] selects of [notebookId] from [store], without
  /// `notebookId`.
  List<VersionRecord> _records(SyncableTable store, String sql, String notebookId) => [
    for (final row in _db.select(sql, [notebookId]))
      (id: row['id'] as String, data: {...store.rowToRecord(row).data!}..remove('notebookId')),
  ];

  /// Writes the table blobs of [rows], noting what each names.
  Future<List<String>> _putTable(List<Map<String, Object?>> rows, WorkSlices slices) async {
    final table = <String>[];
    for (final run in VersionTable.cut(rows)) {
      await slices.yieldIfDue();
      final sha = await blobs.putBytes(VersionTable.encode(run), mime: VersionTable.mime);
      content.links?.add(sha, BlobReferences.inValue(run));
      table.add(sha);
    }
    return table;
  }

  /// The packs of surface [surfaceId] as stored now (from the cache while
  /// its change mark holds and its packs are still here).
  Future<PackedSurface> pack(String surfaceId) async {
    final mark = _markOf(surfaceId);
    final cached = _db.select('SELECT * FROM version_packs WHERE surface_id = ?', [surfaceId]);
    if (cached.isNotEmpty && cached.first['mark'] == mark) {
      final row = cached.first;
      final surface = VersionSurface(
        ink: _list(row['ink'] as String),
        items: _list(row['items'] as String),
      );
      if (surface.packs.every((sha) => blobs.sizeOf(sha) != null)) {
        return (
          surface: surface,
          blobs: _list(row['blobs'] as String),
          strokes: row['strokes'] as int,
        );
      }
    }
    // Read in one go (no await between), so the packs match the mark.
    final ink = _items('strokes', surfaceId);
    final items = _items('elements', surfaceId);
    final media = <String>{for (final (_, data) in items) ...BlobReferences.inValue(data)};
    final surface = VersionSurface(ink: await _put(ink), items: await _put(items));
    final packed = (surface: surface, blobs: media.toList()..sort(), strokes: ink.length);
    _db.execute(
      'INSERT OR REPLACE INTO version_packs (surface_id, mark, ink, items, blobs, strokes, size) '
      'VALUES (?, ?, ?, ?, ?, ?, 0)',
      [
        surfaceId,
        mark,
        jsonEncode(surface.ink),
        jsonEncode(surface.items),
        jsonEncode(packed.blobs),
        packed.strokes,
      ],
    );
    return packed;
  }

  /// Every stroke or element written on [surfaceId] (tombstones too)
  /// changes it.
  String _markOf(String surfaceId) => [
    for (final table in const ['strokes', 'elements'])
      switch (_db.select(
        'SELECT COUNT(*) AS n, MAX(updated_at) AS v FROM $table WHERE surface_id = ?',
        [surfaceId],
      ).first) {
        final row => '${row['n']}:${row['v']}',
      },
  ].join('|');

  /// The live items of [table] on [surfaceId] in paint order.
  List<PackItem> _items(String table, String surfaceId) {
    final store = table == 'strokes' ? repositories.strokes : repositories.elements;
    final items = <PackItem>[
      for (final row in _db.select('SELECT * FROM $table WHERE surface_id = ? AND deleted = 0', [
        surfaceId,
      ]))
        (row['id'] as String, {...store.rowToRecord(row).data!}..remove('surfaceId')),
    ];
    items.sort((a, b) {
      final byTime = (a.$2['createdAt'] as int).compareTo(b.$2['createdAt'] as int);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
    return items;
  }

  Future<List<String>> _put(List<PackItem> items) async => [
    for (final pack in VersionPacks.cut(items))
      await blobs.putBytes(VersionPacks.encode(pack), mime: VersionPacks.mime),
  ];

  static List<String> _list(String json) => (jsonDecode(json) as List).cast<String>();

  /// [made] with its summary against the body before it ([previous]) and
  /// its [size].
  Future<NotebookVersion> _withSummary(
    NotebookVersion made,
    VersionBody body,
    VersionBody? previous,
    int size,
    Map<String, int> counts,
  ) async {
    final before = {for (final p in previous?.pages ?? const <VersionPage>[]) p.id: p};
    final now = {for (final p in body.pages) p.id: p};
    var added = 0, removed = 0, edited = 0, strokesAdded = 0, strokesRemoved = 0;
    String? focus;
    for (final page in body.pages) {
      final old = before[page.id];
      if (old == null) {
        added++;
        strokesAdded += counts[page.id] ?? 0;
        focus ??= page.id;
      } else if (!old.sameAs(page)) {
        edited++;
        focus ??= page.id;
        final (plus, minus) = await _strokeChanges(old.content, page.content);
        strokesAdded += plus;
        strokesRemoved += minus;
      }
    }
    for (final old in before.values) {
      if (now.containsKey(old.id)) continue;
      removed++;
      strokesRemoved += (await _ids(old.content.ink)).length;
    }
    if (body.canvas case final canvas?) {
      final (plus, minus) = await _strokeChanges(previous?.canvas ?? VersionSurface.empty, canvas);
      strokesAdded += plus;
      strokesRemoved += minus;
    }
    return NotebookVersion(
      id: made.id,
      notebookId: made.notebookId,
      createdAt: made.createdAt,
      kind: made.kind,
      name: made.name,
      deviceId: made.deviceId,
      deviceName: made.deviceName,
      notebook: made.notebook,
      table: made.table,
      summary: VersionSummary(
        pages: made.summary.pages,
        strokes: made.summary.strokes,
        pagesAdded: added,
        pagesRemoved: removed,
        pagesEdited: edited,
        strokesAdded: strokesAdded,
        strokesRemoved: strokesRemoved,
        focus: focus,
      ),
      size: size,
    );
  }

  /// Strokes added and removed from [from] to [to]: only the packs that
  /// differ are read (those not on this device count as empty).
  Future<(int, int)> _strokeChanges(VersionSurface from, VersionSurface to) async {
    final kept = from.ink.toSet().intersection(to.ink.toSet());
    final old = await _ids([
      for (final p in from.ink)
        if (!kept.contains(p)) p,
    ]);
    final fresh = await _ids([
      for (final p in to.ink)
        if (!kept.contains(p)) p,
    ]);
    return (fresh.difference(old).length, old.difference(fresh).length);
  }

  Future<Set<String>> _ids(List<String> packs) async => {
    for (final sha in packs)
      ...?switch (await blobs.read(sha)) {
        final Uint8List bytes => VersionPacks.decode(bytes)?.map((item) => item.$1),
        null => null,
      },
  };
}

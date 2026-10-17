import 'package:sqlite3/common.dart';

import '../../domain/notebook.dart';
import '../../domain/notebook_version.dart';
import '../blob_store.dart';
import '../notebook_rows.dart';
import '../page_rows.dart';
import '../repositories.dart';
import '../syncable_table.dart';
import 'surface_packer.dart';
import 'table_runs.dart';
import 'version_content.dart';
import 'version_packs.dart';
import 'version_rows.dart';
import 'version_table.dart';
import 'work_slices.dart';

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
    this.hold,
  }) : _packer = SurfacePacker(repositories: repositories, blobs: blobs),
       _tables = TableRuns(blobs: blobs, links: content.links);

  final Repositories repositories;
  final BlobStore blobs;

  /// Reads versions' bodies (the one before, for the summary) and keeps
  /// the body of a version made here.
  final VersionContent content;

  /// How this device names itself (`Android`).
  final String deviceName;

  /// Whether to pause making a version (a pointer is down: writing).
  final bool Function()? hold;

  final SurfacePacker _packer;
  final TableRuns _tables;

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
    final slices = WorkSlices(hold: hold);
    for (final row in pageRows) {
      await slices.yieldIfDue();
      final id = row['id'] as String;
      final data = PageRows.recordData(row);
      final packed = await pack(id, slices);
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
      final packed = await pack(notebookId, slices);
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
    final table = await _tables.put(notebookId, VersionTable.rowsOf(body, notebookId), slices);
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
    return _withSummary(made, body, before, size, counts, slices);
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

  /// The packs of surface [surfaceId] as stored now ([SurfacePacker.pack]).
  Future<PackedSurface> pack(String surfaceId, [WorkSlices? slices]) =>
      _packer.pack(surfaceId, slices);

  /// [made] with its summary against the body before it ([previous]) and
  /// its [size].
  Future<NotebookVersion> _withSummary(
    NotebookVersion made,
    VersionBody body,
    VersionBody? previous,
    int size,
    Map<String, int> counts,
    WorkSlices slices,
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
        final (plus, minus) = await _strokeChanges(old.content, page.content, slices);
        strokesAdded += plus;
        strokesRemoved += minus;
      }
    }
    for (final old in before.values) {
      if (now.containsKey(old.id)) continue;
      removed++;
      strokesRemoved += (await _ids(old.content.ink, slices)).length;
    }
    if (body.canvas case final canvas?) {
      final (plus, minus) = previous?.canvas == null
          ? (counts[made.notebookId] ?? 0, 0)
          : await _strokeChanges(previous!.canvas!, canvas, slices);
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
  Future<(int, int)> _strokeChanges(
    VersionSurface from,
    VersionSurface to,
    WorkSlices slices,
  ) async {
    final kept = from.ink.toSet().intersection(to.ink.toSet());
    final old = await _ids([
      for (final p in from.ink)
        if (!kept.contains(p)) p,
    ], slices);
    final fresh = await _ids([
      for (final p in to.ink)
        if (!kept.contains(p)) p,
    ], slices);
    return (fresh.difference(old).length, old.difference(fresh).length);
  }

  Future<Set<String>> _ids(List<String> packs, WorkSlices slices) async {
    final ids = <String>{};
    for (final sha in packs) {
      await slices.yieldIfDue();
      if (await blobs.read(sha) case final bytes?) {
        ids.addAll(VersionPacks.decode(bytes)?.map((item) => item.$1) ?? const []);
      }
    }
    return ids;
  }
}

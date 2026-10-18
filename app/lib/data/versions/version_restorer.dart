import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/notebook.dart';
import '../../domain/notebook_page.dart';
import '../../domain/notebook_version.dart';
import '../../domain/paper.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../page_order.dart';
import '../page_rows.dart';
import '../repositories.dart';
import '../syncable_table.dart';
import 'version_content.dart';
import 'version_records.dart';
import 'version_snapshots.dart';

/// What a restore did: the version saved before it (restoring that one
/// undoes it) and the surfaces it rewrote, for open editors to reload.
typedef Restored = ({NotebookVersion? before, Set<String> surfaces, bool pages});

/// Restores versions (docs/ARCHITECTURE.md, "Version history"): the whole
/// notebook, one page, or a copy as a new notebook. Restoring writes local
/// edits (synced like any) and first saves the current state as a
/// [VersionKind.restore] version, so nothing is lost.
class VersionRestorer {
  VersionRestorer({required this.repositories, required this.snapshots, required this.content});

  final Repositories repositories;
  final VersionSnapshots snapshots;
  final VersionContent content;

  /// Makes notebook [version.notebookId] what [version] holds: settings,
  /// pages (or canvas) and, unless the version is of format 1, its
  /// recordings, outline and recognised handwriting. Throws
  /// [VersionUnavailable] (changing nothing) when its content can't be had.
  Future<Restored> restore(NotebookVersion version) async {
    final body = await content.body(version);
    final loaded = await _load(body, body.pages);
    final canvas = body.canvas == null
        ? null
        : await content.load(body.canvas!, version.notebookId, strict: true);
    final r = repositories;
    final surfaces = <String>{};
    final before = await _beforeAnd(version, () {
      final notebook = r.notebooks.get(version.notebookId);
      if (notebook == null) return;
      final restored = VersionContent.settingsOn(notebook, version);
      if (!_sameSettings(restored, notebook)) r.notebooks.update(restored);
      if (canvas != null) {
        _surface(version.notebookId, canvas);
        _text(version.notebookId, body.canvas!, body);
        surfaces.add(version.notebookId);
      } else {
        _pages(version, body, loaded);
        surfaces.addAll(loaded.keys);
      }
      if (body.recordings case final recordings?) {
        _records(r.recordings, version.notebookId, recordings);
      }
      if (body.outline case final outline?) _records(r.outline, version.notebookId, outline);
      r.notebooks.touch(version.notebookId);
    });
    return (before: before, surfaces: surfaces, pages: canvas == null);
  }

  /// Makes page [pageId] what [version] holds of it (back where it was
  /// among the pages it followed if it is gone), with its recognised
  /// handwriting and the outline entries leading to it.
  Future<Restored> restorePage(NotebookVersion version, String pageId) async {
    final body = await content.body(version);
    final page = body.page(pageId)!;
    final loaded = await _load(body, [page]);
    final r = repositories;
    final before = await _beforeAnd(version, () {
      final live = {for (final p in r.pages.pagesOf(version.notebookId)) p.id: p};
      final key = live[pageId]?.sortKey ?? _keyAfterPredecessor(body, pageId, live);
      _writePage(VersionContent.pageOf(version, page, sortKey: key), live[pageId]);
      _surface(pageId, loaded[pageId]!);
      _text(pageId, page.content, body);
      if (body.outline case final outline?) {
        _records(r.outline, version.notebookId, [
          for (final e in outline)
            if (e.data['pageId'] == pageId) e,
        ], removeOthers: false);
      }
      r.notebooks.touch(version.notebookId);
    });
    return (before: before, surfaces: {pageId}, pages: true);
  }

  /// Writes [version] as a new notebook (new ids throughout, links among
  /// its pages, text flows and connectors following them, its recordings
  /// and outline too); returns it.
  Future<Notebook?> copy(NotebookVersion version, {required String title}) async {
    final r = repositories;
    final body = await content.body(version);
    final source = r.notebooks.get(version.notebookId);
    final clock = r.notebooks.clock;
    final renamed = <String, String>{version.notebookId: clock.newId()};
    final surfaces = [
      for (final p in body.pages) (p.content, p.id),
      if (body.canvas case final canvas?) (canvas, version.notebookId),
    ];
    await content.ensure([for (final (s, _) in surfaces) s]);
    for (final (surface, id) in surfaces) {
      renamed.putIfAbsent(id, clock.newId);
      for (final item in await content.itemIds(surface)) {
        renamed[item] = clock.newId();
      }
    }
    final loaded = [
      for (final (surface, id) in surfaces)
        await content.load(
          surface,
          renamed[id]!,
          strict: true,
          renamed: renamed,
          newId: clock.newId,
        ),
    ];
    final now = clock.nowMs();
    final copyId = renamed[version.notebookId]!;
    final kind = NotebookKind.parse(version.notebook['kind'] as String);
    final base = Notebook(
      id: copyId,
      title: title,
      kind: kind,
      paper: Paper.blank,
      coverColor: 0,
      createdAt: now,
      updatedAt: now,
      folderId: source?.folderId,
    );
    final notebook = VersionContent.settingsOn(base, version).copyWith(title: title);
    r.versions.database.transaction(() {
      r.notebooks.update(notebook);
      for (final (i, page) in body.pages.indexed) {
        final p = VersionContent.pageOf(version, page, sortKey: i + 1.0);
        PageRows.insert(
          r.pages.database,
          NotebookPage(
            id: renamed[page.id]!,
            notebookId: copyId,
            sortKey: p.sortKey,
            width: p.width,
            height: p.height,
            paper: p.paper,
            paperColor: p.paperColor,
            bookmarked: p.bookmarked,
            background: p.background,
          ),
          updatedAt: now,
          deviceId: r.pages.deviceId,
          dirty: true,
        );
      }
      for (final c in loaded) {
        r.strokes.save(c.strokes);
        r.elements.save(c.elements);
      }
      VersionRecords.copy(r, body, copyId, renamed, clock.newId);
    });
    return r.notebooks.get(copyId);
  }

  /// The surfaces of [pages], loaded whole (else nothing is restored).
  Future<Map<String, SurfaceContent>> _load(VersionBody body, List<VersionPage> pages) async {
    await content.ensure([for (final p in pages) p.content, ?body.canvas]);
    return {for (final p in pages) p.id: await content.load(p.content, p.id, strict: true)};
  }

  /// Saves the notebook as it is now as a [VersionKind.restore] version
  /// and runs [restore] in the same transaction; returns that version.
  ///
  /// The version is made across turns, while sync (or an edit) may write
  /// to the notebook, and the restore would remove what the version lacks.
  /// So it is saved, and the restore run, only if nothing in the notebook
  /// changed since it began; else it is made again. If it changed on the
  /// last of [attempts] too, the version is made once more in that
  /// transaction, in one turn ([VersionSnapshots.buildNow]): a long turn,
  /// but nothing can write in between, so nothing is lost. Its new blobs
  /// are stored, and its summary completed, after it.
  Future<NotebookVersion?> _beforeAnd(NotebookVersion version, void Function() restore) async {
    final db = repositories.versions.database;
    final id = version.notebookId;
    for (var attempt = 1; ; attempt++) {
      db.steps.finish();
      final mark = _stateOf(id);
      final built = await snapshots.build(id, kind: VersionKind.restore);
      debugBuilt?.call(attempt);
      Future<NotebookVersion> Function()? finish;
      final done = db.transaction(() {
        var before = built;
        if (_stateOf(id) != mark) {
          if (attempt < attempts) return null;
          final now = snapshots.buildNow(id, kind: VersionKind.restore);
          before = now?.version;
          finish = now?.finish;
        }
        if (before != null) repositories.versions.save(before);
        restore();
        return (before,);
      });
      if (done == null) continue;
      if (finish case final finish?) {
        final finished = await finish();
        repositories.versions.save(finished);
        return finished;
      }
      return done.$1;
    }
  }

  /// Told after each try has made its version (and before it is checked);
  /// tests write to the notebook there.
  @visibleForTesting
  void Function(int attempt)? debugBuilt;

  /// How often a restore makes the version before it while the notebook
  /// keeps changing.
  static const attempts = 4;

  /// A mark of everything stored of notebook [id] (tombstones too) that
  /// changes with every write to it.
  String _stateOf(String id) {
    const ofRows = "COUNT(*) || ':' || COALESCE(SUM(updated_at), 0) || ':' || TOTAL(deleted)";
    const surfaces = 'SELECT id FROM pages WHERE notebook_id = ?1 UNION ALL SELECT ?1';
    final row = repositories.versions.db
        .select(
          '''
      SELECT
        (SELECT $ofRows FROM notebooks WHERE id = ?1) AS n,
        (SELECT $ofRows FROM pages WHERE notebook_id = ?1) AS p,
        (SELECT $ofRows FROM strokes WHERE surface_id IN ($surfaces)) AS s,
        (SELECT $ofRows FROM elements WHERE surface_id IN ($surfaces)) AS e,
        (SELECT $ofRows FROM recognised_text WHERE id IN ($surfaces)) AS t,
        (SELECT $ofRows FROM recordings WHERE notebook_id = ?1) AS r,
        (SELECT $ofRows FROM outline WHERE notebook_id = ?1) AS o''',
          [id],
        )
        .first;
    return row.values.join('|');
  }

  static bool _sameSettings(Notebook a, Notebook b) =>
      a.title == b.title &&
      a.paperColor == b.paperColor &&
      a.coverColor == b.coverColor &&
      jsonEncode(a.paper.toData()) == jsonEncode(b.paper.toData()) &&
      a.paper.style == b.paper.style;

  /// Restores every page of [version]: in its order, kept pages rewritten
  /// where they differ, gone ones written back, others deleted.
  void _pages(NotebookVersion version, VersionBody body, Map<String, SurfaceContent> loaded) {
    final r = repositories;
    final live = {for (final p in r.pages.pagesOf(version.notebookId)) p.id: p};
    final keys = _keysFor(body, live);
    for (final (i, page) in body.pages.indexed) {
      _writePage(VersionContent.pageOf(version, page, sortKey: keys[i]), live[page.id]);
      _surface(page.id, loaded[page.id]!);
      _text(page.id, page.content, body);
    }
    final kept = {for (final p in body.pages) p.id};
    for (final id in live.keys) {
      if (!kept.contains(id)) r.notebooks.deletePage(id);
    }
  }

  /// Sort keys for [version]'s pages: the live ones keep theirs while they
  /// are in the version's order, gone ones fit between; else 1, 2, ….
  static List<double> _keysFor(VersionBody body, Map<String, NotebookPage> live) {
    final pages = body.pages;
    final keys = List<double?>.filled(pages.length, null);
    double? last;
    var ordered = true;
    for (final (i, p) in pages.indexed) {
      final key = live[p.id]?.sortKey;
      if (key == null) continue;
      if (last != null && key <= last) ordered = false;
      keys[i] = last = key;
    }
    if (ordered) {
      for (var i = 0; i < pages.length && ordered; i++) {
        if (keys[i] != null) continue;
        final before = i > 0 ? keys[i - 1] : null;
        final after = keys.skip(i + 1).nonNulls.firstOrNull;
        final key = PageOrder.between(before, after);
        if (key == null) ordered = false;
        keys[i] = key;
      }
    }
    if (!ordered) return [for (var i = 0; i < pages.length; i++) i + 1.0];
    return keys.cast<double>();
  }

  /// A key putting page [pageId] of [version] after the nearest page
  /// before it there that is still live (first if none).
  static double _keyAfterPredecessor(
    VersionBody body,
    String pageId,
    Map<String, NotebookPage> live,
  ) {
    final index = body.pages.indexWhere((p) => p.id == pageId);
    final ordered = live.values.toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    NotebookPage? before;
    for (final p in body.pages.take(index).toList().reversed) {
      if (live[p.id] case final page?) {
        before = page;
        break;
      }
    }
    final at = before == null ? 0 : ordered.indexOf(before) + 1;
    return PageOrder.between(
          at > 0 ? ordered[at - 1].sortKey : null,
          at < ordered.length ? ordered[at].sortKey : null,
        ) ??
        (ordered.isEmpty ? 1 : ordered.last.sortKey + 1);
  }

  void _text(String surfaceId, VersionSurface surface, VersionBody body) {
    if (body.recordings != null) VersionRecords.restoreText(repositories, surfaceId, surface.text);
  }

  void _records(
    SyncableTable store,
    String notebookId,
    List<VersionRecord> records, {
    bool removeOthers = true,
  }) => VersionRecords.restore(store, notebookId, records, removeOthers: removeOthers);

  /// Writes [page] unless [live] is it already.
  void _writePage(NotebookPage page, NotebookPage? live) {
    final r = repositories;
    if (live != null && _samePage(page, live)) return;
    PageRows.insert(
      r.pages.database,
      page,
      updatedAt: r.pages.nextVersion(page.id),
      deviceId: r.pages.deviceId,
      dirty: true,
    );
  }

  static bool _samePage(NotebookPage a, NotebookPage b) =>
      a.sortKey == b.sortKey &&
      a.width == b.width &&
      a.height == b.height &&
      a.paper.style == b.paper.style &&
      jsonEncode(a.paper.toData()) == jsonEncode(b.paper.toData()) &&
      a.paperColor == b.paperColor &&
      a.bookmarked == b.bookmarked &&
      jsonEncode(a.background?.toJson()) == jsonEncode(b.background?.toJson());

  /// Makes surface [surfaceId]'s live strokes and elements those of
  /// [target]: by id, the rest tombstoned.
  void _surface(String surfaceId, SurfaceContent target) {
    final r = repositories;
    final db = r.strokes.db;
    final liveStrokes = {
      for (final row in db.select('SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0', [
        surfaceId,
      ]))
        row['id'] as String,
    };
    final wanted = {for (final s in target.strokes) s.id: s};
    r.strokes.delete(liveStrokes.where((id) => !wanted.containsKey(id)).toList());
    r.strokes.save(<Stroke>[
      for (final s in target.strokes)
        if (!liveStrokes.contains(s.id)) s,
    ]);
    final liveElements = {for (final e in r.elements.allOn(surfaceId)) e.id: e};
    final elements = {for (final e in target.elements) e.id: e};
    r.elements.delete(liveElements.keys.where((id) => !elements.containsKey(id)).toList());
    r.elements.save(<SurfaceElement>[
      for (final e in target.elements)
        if (liveElements[e.id] case final live when live == null || !_sameElement(live, e)) e,
    ]);
  }

  static bool _sameElement(SurfaceElement a, SurfaceElement b) =>
      a.type == b.type &&
      a.rect == b.rect &&
      a.rotation == b.rotation &&
      a.z == b.z &&
      a.createdAt == b.createdAt &&
      jsonEncode(a.data) == jsonEncode(b.data);
}

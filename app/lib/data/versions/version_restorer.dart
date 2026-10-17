import 'dart:convert';

import '../../domain/notebook.dart';
import '../../domain/notebook_page.dart';
import '../../domain/notebook_version.dart';
import '../../domain/paper.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../page_order.dart';
import '../page_rows.dart';
import '../repositories.dart';
import 'version_content.dart';
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

  /// Makes notebook [version.notebookId] what [version] holds. Throws
  /// [VersionUnavailable] (changing nothing) when its content can't be had.
  Future<Restored> restore(NotebookVersion version) async {
    final loaded = await _load(version, version.pages);
    final canvas = version.canvas == null
        ? null
        : await content.load(version.canvas!, version.notebookId, strict: true);
    final before = await _before(version);
    final r = repositories;
    final surfaces = <String>{};
    r.versions.database.transaction(() {
      final notebook = r.notebooks.get(version.notebookId);
      if (notebook == null) return;
      final restored = VersionContent.settingsOn(notebook, version);
      if (!_sameSettings(restored, notebook)) r.notebooks.update(restored);
      if (canvas != null) {
        _surface(version.notebookId, canvas);
        surfaces.add(version.notebookId);
      } else {
        _pages(version, loaded);
        surfaces.addAll(loaded.keys);
      }
      r.notebooks.touch(version.notebookId);
    });
    return (before: before, surfaces: surfaces, pages: canvas == null);
  }

  /// Makes page [pageId] what [version] holds of it (back where it was
  /// among the pages it followed if it is gone).
  Future<Restored> restorePage(NotebookVersion version, String pageId) async {
    final page = version.pages.firstWhere((p) => p.id == pageId);
    final loaded = await _load(version, [page]);
    final before = await _before(version);
    final r = repositories;
    r.versions.database.transaction(() {
      final live = {for (final p in r.pages.pagesOf(version.notebookId)) p.id: p};
      final key = live[pageId]?.sortKey ?? _keyAfterPredecessor(version, pageId, live);
      _writePage(VersionContent.pageOf(version, page, sortKey: key), live[pageId]);
      _surface(pageId, loaded[pageId]!);
      r.notebooks.touch(version.notebookId);
    });
    return (before: before, surfaces: {pageId}, pages: true);
  }

  /// Writes [version] as a new notebook (new ids throughout, links among
  /// its pages, text flows and connectors following them); returns it.
  Future<Notebook?> copy(NotebookVersion version, {required String title}) async {
    final r = repositories;
    final source = r.notebooks.get(version.notebookId);
    final clock = r.notebooks.clock;
    final renamed = <String, String>{version.notebookId: clock.newId()};
    final surfaces = [
      for (final p in version.pages) (p.content, p.id),
      if (version.canvas case final canvas?) (canvas, version.notebookId),
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
      for (final (i, page) in version.pages.indexed) {
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
    });
    return r.notebooks.get(copyId);
  }

  /// The surfaces of [pages], loaded whole (else nothing is restored).
  Future<Map<String, SurfaceContent>> _load(
    NotebookVersion version,
    List<VersionPage> pages,
  ) async {
    await content.ensure([for (final p in pages) p.content, ?version.canvas]);
    return {for (final p in pages) p.id: await content.load(p.content, p.id, strict: true)};
  }

  /// Saves the notebook as it is now, before a restore changes it.
  Future<NotebookVersion?> _before(NotebookVersion version) =>
      snapshots.take(version.notebookId, kind: VersionKind.restore, force: true);

  static bool _sameSettings(Notebook a, Notebook b) =>
      a.title == b.title &&
      a.paperColor == b.paperColor &&
      a.coverColor == b.coverColor &&
      jsonEncode(a.paper.toData()) == jsonEncode(b.paper.toData()) &&
      a.paper.style == b.paper.style;

  /// Restores every page of [version]: in its order, kept pages rewritten
  /// where they differ, gone ones written back, others deleted.
  void _pages(NotebookVersion version, Map<String, SurfaceContent> loaded) {
    final r = repositories;
    final live = {for (final p in r.pages.pagesOf(version.notebookId)) p.id: p};
    final keys = _keysFor(version, live);
    for (final (i, page) in version.pages.indexed) {
      _writePage(VersionContent.pageOf(version, page, sortKey: keys[i]), live[page.id]);
      _surface(page.id, loaded[page.id]!);
    }
    final kept = {for (final p in version.pages) p.id};
    for (final id in live.keys) {
      if (!kept.contains(id)) r.notebooks.deletePage(id);
    }
  }

  /// Sort keys for [version]'s pages: the live ones keep theirs while they
  /// are in the version's order, gone ones fit between; else 1, 2, ….
  static List<double> _keysFor(NotebookVersion version, Map<String, NotebookPage> live) {
    final pages = version.pages;
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
    NotebookVersion version,
    String pageId,
    Map<String, NotebookPage> live,
  ) {
    final index = version.pages.indexWhere((p) => p.id == pageId);
    final ordered = live.values.toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    NotebookPage? before;
    for (final p in version.pages.take(index).toList().reversed) {
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

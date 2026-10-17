import 'package:flutter/foundation.dart';

import '../../domain/notebook.dart';
import '../../domain/notebook_version.dart';
import '../blob_store.dart';
import '../repositories.dart';
import '../tombstone_payloads.dart';
import 'version_content.dart';
import 'version_policy.dart';
import 'version_repository.dart';
import 'version_restorer.dart';
import 'version_snapshots.dart';

export '../../domain/notebook_version.dart';
export 'version_content.dart' show SurfaceContent, VersionContent, VersionUnavailable;
export 'version_restorer.dart' show Restored;

/// Version history (docs/ARCHITECTURE.md, "Version history"): making,
/// thinning, reading, restoring and deleting notebooks' versions. Tells
/// its listeners when versions made or deleted here change a notebook's
/// history (pulled ones come with `RemoteChanges.versionsOfNotebooks`).
class Versions extends ChangeNotifier {
  Versions({
    required this.repositories,
    required BlobStore blobs,
    required String deviceName,
    Future<bool> Function(String sha)? fetch,
  }) : snapshots = VersionSnapshots(
         repositories: repositories,
         blobs: blobs,
         deviceName: deviceName,
       ),
       content = VersionContent(blobs: blobs, fetch: fetch);

  final Repositories repositories;
  final VersionSnapshots snapshots;
  final VersionContent content;
  late final VersionRestorer restorer = VersionRestorer(
    repositories: repositories,
    snapshots: snapshots,
    content: content,
  );

  VersionRepository get store => repositories.versions;

  /// The versions of [notebookId], newest first.
  List<NotebookVersion> of(String notebookId) => store.of(notebookId);

  /// Makes an automatic version of [notebookId] if it changed since its
  /// newest one, then thins its history.
  Future<NotebookVersion?> record(String notebookId) async {
    final made = await snapshots.take(notebookId);
    if (made == null) return null;
    thin(notebookId);
    notifyListeners();
    return made;
  }

  /// Saves a named version of [notebookId] now (even if nothing changed).
  Future<NotebookVersion?> save(String notebookId, {required String name}) async {
    final made = await snapshots.take(
      notebookId,
      kind: VersionKind.named,
      name: name.trim().isEmpty ? null : name.trim(),
      force: true,
    );
    notifyListeners();
    return made;
  }

  /// Names version [id] (empty: no name).
  void rename(String id, String name) {
    store.rename(id, name.trim().isEmpty ? null : name.trim());
    notifyListeners();
  }

  /// Deletes versions [ids].
  void delete(Iterable<String> ids) {
    store.delete(ids);
    notifyListeners();
  }

  /// The versions of [version]'s notebook older than it.
  List<NotebookVersion> olderThan(NotebookVersion version) => [
    for (final v in of(version.notebookId))
      if (v.createdAt < version.createdAt) v,
  ];

  /// Removes what [VersionPolicy] does not keep of [notebookId]'s history.
  void thin(String notebookId) {
    final remove = VersionPolicy.toRemove(store.infosOf(notebookId), store.clock.nowMs());
    if (remove.isNotEmpty) store.delete(remove);
  }

  /// Thins every notebook's history, and removes the versions of notebooks
  /// deleted forever longer ago than deletion conflicts may bring them back
  /// ([TombstonePayloads.retention]). Run with blob garbage collection.
  void maintain() {
    final since = TombstonePayloads.keptSince(store.clock.nowMs());
    final db = store.db;
    for (final id in store.notebooks()) {
      final gone = db.select(
        'SELECT 1 FROM notebooks WHERE id = ? AND deleted = 1 AND updated_at < ?',
        [id, since],
      ).isNotEmpty;
      if (gone) {
        store.delete([for (final v in store.infosOf(id)) v.id]);
      } else {
        thin(id);
      }
    }
  }

  /// Restores the whole notebook to [version] (see [VersionRestorer]).
  Future<Restored> restore(NotebookVersion version) async {
    final done = await restorer.restore(version);
    notifyListeners();
    return done;
  }

  /// Restores page [pageId] as [version] holds it.
  Future<Restored> restorePage(NotebookVersion version, String pageId) async {
    final done = await restorer.restorePage(version, pageId);
    notifyListeners();
    return done;
  }

  /// Copies [version] as a new notebook titled [title].
  Future<Notebook?> copy(NotebookVersion version, {required String title}) =>
      restorer.copy(version, title: title);
}

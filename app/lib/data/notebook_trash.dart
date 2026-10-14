part of 'notebook_repository.dart';

/// The trash: notebooks kept for a while before they are deleted forever.
mixin _NotebookTrash on SyncableTable {
  List<Notebook> list();
  List<Notebook> trashed();
  void delete(String id);
  void _change(String id, Notebook Function(Notebook) change);

  /// Moves a notebook to the trash; it can be restored until deleted forever.
  void trash(String id) => _change(id, (n) => n.copyWith(trashedAt: clock.nowMs()));

  /// Takes a notebook out of the trash. If its folder no longer exists it
  /// returns to the library root.
  void restore(String id) => _change(id, (n) {
    final folder = n.folderId;
    final folderAlive =
        folder != null &&
        db.select('SELECT 1 FROM folders WHERE id = ? AND deleted = 0', [folder]).isNotEmpty;
    return n.copyWith(trashedAt: null, folderId: folderAlive ? folder : null);
  });

  /// Moves every notebook inside [folderIds] to the trash (folder deletion);
  /// returns the ids of those it trashed (not those already in the trash).
  List<String> trashAllIn(Set<String> folderIds) {
    if (folderIds.isEmpty) return const [];
    return database.transaction(
      () => [
        for (final n in list())
          if (folderIds.contains(n.folderId)) n.id,
      ]..forEach(trash),
    );
  }

  /// Ids of the notebooks trashed more than [NotebookRepository.trashKeptFor] ago, the
  /// oldest first.
  List<String> expiredTrash() => [
    for (final r in db.select(
      'SELECT id FROM notebooks WHERE deleted = 0 AND trashed_at < ? ORDER BY trashed_at, id',
      [_trashExpiry],
    ))
      r['id'] as String,
  ];

  int get _trashExpiry => clock.nowMs() - NotebookRepository.trashKeptFor.inMilliseconds;

  /// Deletes notebook [id] forever if it is still in the trash and was
  /// trashed more than [NotebookRepository.trashKeptFor] ago; returns whether it did.
  bool purgeIfExpired(String id) {
    final expired = db.select(
      'SELECT 1 FROM notebooks WHERE id = ? AND deleted = 0 AND trashed_at < ?',
      [id, _trashExpiry],
    ).isNotEmpty;
    if (expired) delete(id);
    return expired;
  }

  /// Deletes forever the notebooks trashed more than [NotebookRepository.trashKeptFor] ago;
  /// returns how many.
  int purgeTrash() => database.transaction(() => expiredTrash().where(purgeIfExpired).length);

  /// Permanently deletes every notebook in the trash.
  void emptyTrash() {
    database.transaction(() {
      for (final n in trashed()) {
        delete(n.id);
      }
    });
  }
}

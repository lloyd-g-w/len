import 'remote_changes.dart';

/// What to tell the user whose deletions another device undid by writing
/// in what was deleted (UX_AUDIT R16-6; `DeletionConflicts`): a notebook
/// deleted forever is back in the trash, deleted pages are back in their
/// notebook. One line each; none when nothing of this device's came back.
/// [titleOf] names a notebook (null: gone again since).
List<String> revivalNotices(RemoteChanges changes, String? Function(String id) titleOf) {
  final notices = <String>[];
  final notebooks = changes.undoneNotebooks;
  if (notebooks.length == 1) {
    final title = titleOf(notebooks.single);
    notices.add(
      '${title == null ? 'A notebook you deleted' : '“$title”'} is back in the trash: '
      'another device wrote in it after you deleted it',
    );
  } else if (notebooks.length > 1) {
    notices.add(
      '${notebooks.length} notebooks you deleted are back in the trash: '
      'another device wrote in them',
    );
  }
  final pages = {
    for (final MapEntry(:key, :value) in changes.undonePages.entries)
      if (!notebooks.contains(key)) key: value,
  };
  final count = pages.values.fold(0, (a, b) => a + b.length);
  if (count == 0) return notices;
  final title = pages.length == 1 ? titleOf(pages.keys.single) : null;
  final where = title == null ? '' : ' in “$title”';
  notices.add(
    count == 1
        ? 'A page you deleted$where is back: another device wrote on it'
        : '$count pages you deleted$where are back: another device wrote on them',
  );
  return notices;
}

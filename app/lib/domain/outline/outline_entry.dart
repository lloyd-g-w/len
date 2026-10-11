/// An entry of a notebook's own outline (table of contents): a titled link
/// to one of its pages, possibly nested under another entry (collection
/// `outline`).
///
/// Entries have no stored order: siblings follow the order of their pages
/// in the notebook (see [OutlineTree]), so the outline stays in step when
/// pages are reordered, and two devices adding entries never conflict.
class OutlineEntry {
  const OutlineEntry({
    required this.id,
    required this.notebookId,
    required this.pageId,
    required this.parentId,
    required this.title,
    required this.createdAt,
  });

  final String id;
  final String notebookId;

  /// The page the entry opens (it may since have been deleted).
  final String pageId;

  /// The entry this one is nested under; null at the top level.
  final String? parentId;
  final String title;

  /// Milliseconds since epoch; orders entries of the same page.
  final int createdAt;

  static const Object _keep = Object();

  /// A copy with the given fields replaced; `parentId: null` moves it to
  /// the top level.
  OutlineEntry copyWith({String? title, Object? parentId = _keep, String? pageId}) => OutlineEntry(
    id: id,
    notebookId: notebookId,
    pageId: pageId ?? this.pageId,
    parentId: identical(parentId, _keep) ? this.parentId : parentId as String?,
    title: title ?? this.title,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is OutlineEntry &&
      other.id == id &&
      other.notebookId == notebookId &&
      other.pageId == pageId &&
      other.parentId == parentId &&
      other.title == title &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, notebookId, pageId, parentId, title, createdAt);
}

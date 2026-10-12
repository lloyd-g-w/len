import 'paper.dart';

/// Whether a notebook is a sequence of fixed-size pages or a single
/// unbounded canvas.
enum NotebookKind {
  paged,
  canvas;

  static NotebookKind parse(String value) =>
      values.firstWhere((k) => k.name == value, orElse: () => paged);
}

/// A notebook as shown in the library.
///
/// For [NotebookKind.canvas] notebooks the notebook id doubles as the
/// surface id that strokes belong to. Paged notebooks own [NotebookPage]s,
/// each of which is its own surface.
class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.kind,
    required this.paper,
    required this.coverColor,
    required this.createdAt,
    required this.updatedAt,
    this.paperColor = PaperColor.white,
    this.folderId,
    this.favorite = false,
    this.trashedAt,
    int? editedAt,
  }) : editedAt = editedAt ?? updatedAt;

  final String id;
  final String title;
  final NotebookKind kind;

  /// Default paper for new pages (paged) or the canvas background (canvas):
  /// a template without parameters (not a planner or image), with its look.
  final Paper paper;

  /// Colour of the canvas background (canvas notebooks; pages of paged
  /// notebooks carry their own colour).
  final PaperColor paperColor;

  /// ARGB colour of the cover in the library.
  final int coverColor;

  /// Milliseconds since epoch.
  final int createdAt;

  /// Milliseconds since epoch of the last change of any kind; also the
  /// last-write-wins version used by sync.
  final int updatedAt;

  /// Milliseconds since epoch of the last title or content edit. Unlike
  /// [updatedAt] it ignores organisation (favourite, move, trash), so
  /// "last edited" sorting does not jump around.
  final int editedAt;

  /// Containing folder, or null for the library root.
  final String? folderId;

  /// Starred by the user.
  final bool favorite;

  /// When the notebook was moved to the trash, or null if it is not trashed.
  final int? trashedAt;

  bool get isTrashed => trashedAt != null;

  static const Object _keep = Object();

  /// A copy with the given fields replaced. Pass `folderId: null` /
  /// `trashedAt: null` explicitly to clear them.
  Notebook copyWith({
    String? title,
    Paper? paper,
    PaperColor? paperColor,
    int? coverColor,
    int? updatedAt,
    int? editedAt,
    Object? folderId = _keep,
    bool? favorite,
    Object? trashedAt = _keep,
  }) {
    return Notebook(
      id: id,
      title: title ?? this.title,
      kind: kind,
      paper: paper ?? this.paper,
      paperColor: paperColor ?? this.paperColor,
      coverColor: coverColor ?? this.coverColor,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      editedAt: editedAt ?? this.editedAt,
      folderId: identical(folderId, _keep) ? this.folderId : folderId as String?,
      favorite: favorite ?? this.favorite,
      trashedAt: identical(trashedAt, _keep) ? this.trashedAt : trashedAt as int?,
    );
  }
}

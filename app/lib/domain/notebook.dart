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
  });

  final String id;
  final String title;
  final NotebookKind kind;

  /// Default paper for new pages (paged) or the canvas background (canvas).
  final PaperStyle paper;

  /// ARGB colour of the cover in the library.
  final int coverColor;

  /// Milliseconds since epoch.
  final int createdAt;

  /// Milliseconds since epoch of the last metadata or content change.
  final int updatedAt;

  Notebook copyWith({
    String? title,
    PaperStyle? paper,
    int? coverColor,
    int? updatedAt,
  }) {
    return Notebook(
      id: id,
      title: title ?? this.title,
      kind: kind,
      paper: paper ?? this.paper,
      coverColor: coverColor ?? this.coverColor,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

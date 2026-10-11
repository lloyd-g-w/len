import 'dart:ui';

import 'paper.dart';

/// Content drawn underneath the paper pattern and ink of a page, e.g. a
/// page of an imported PDF. Large data lives in a content-addressed blob.
class PageBackground {
  const PageBackground.pdf({required this.blob, required this.pageIndex});

  /// SHA-256 (lowercase hex) of the PDF file.
  final String blob;

  /// Zero-based page number within the PDF.
  final int pageIndex;

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  Map<String, Object?> toJson() => {'type': 'pdf', 'blob': blob, 'page': pageIndex};

  /// Parses a stored background; null if [json] is not a valid one.
  static PageBackground? fromJson(Object? json) {
    if (json is! Map) return null;
    final blob = json['blob'];
    final page = json['page'];
    if (json['type'] != 'pdf' || blob is! String || !_sha256.hasMatch(blob)) return null;
    if (page is! int || page < 0) return null;
    return PageBackground.pdf(blob: blob, pageIndex: page);
  }

  @override
  bool operator ==(Object other) =>
      other is PageBackground && other.blob == blob && other.pageIndex == pageIndex;

  @override
  int get hashCode => Object.hash(blob, pageIndex);
}

/// One page of a paged notebook. Its [id] is the surface id of its strokes.
class NotebookPage {
  const NotebookPage({
    required this.id,
    required this.notebookId,
    required this.sortKey,
    required this.width,
    required this.height,
    required this.paper,
    this.paperColor = PaperColor.white,
    this.bookmarked = false,
    this.background,
  });

  final String id;
  final String notebookId;

  /// Pages are ordered by ascending sort key. Fractional keys allow inserting
  /// between two pages without renumbering (and without sync conflicts).
  final double sortKey;

  final double width;
  final double height;
  final PaperStyle paper;
  final PaperColor paperColor;
  final bool bookmarked;
  final PageBackground? background;

  /// The page area in world coordinates.
  Rect get bounds => Rect.fromLTWH(0, 0, width, height);

  Size get size => Size(width, height);

  /// A template describing this page, for creating similar pages.
  PageTemplate get template {
    final match = PageFormat.match(size);
    return PageTemplate(
      style: paper,
      color: paperColor,
      format: match?.format ?? PageFormat.a4,
      orientation:
          match?.orientation ??
          (width > height ? PageOrientation.landscape : PageOrientation.portrait),
    );
  }

  NotebookPage copyWith({
    double? sortKey,
    PaperStyle? paper,
    PaperColor? paperColor,
    bool? bookmarked,
  }) => NotebookPage(
    id: id,
    notebookId: notebookId,
    sortKey: sortKey ?? this.sortKey,
    width: width,
    height: height,
    paper: paper ?? this.paper,
    paperColor: paperColor ?? this.paperColor,
    bookmarked: bookmarked ?? this.bookmarked,
    background: background,
  );
}

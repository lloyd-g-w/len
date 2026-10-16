import 'dart:ui';

import 'paper.dart';

/// What a [PageBackground] shows.
enum PageBackgroundKind {
  /// A page of an imported PDF.
  pdf,

  /// A picture filling the page, e.g. a scanned document.
  image,
}

/// Content drawn underneath the paper pattern and ink of a page: a page of
/// an imported PDF or an image (a scanned document). Large data lives in a
/// content-addressed blob.
class PageBackground {
  const PageBackground.pdf({required this.blob, required this.pageIndex})
    : kind = PageBackgroundKind.pdf;

  /// An image (PNG / JPEG / WebP blob) stretched over the whole page.
  const PageBackground.image({required this.blob}) : kind = PageBackgroundKind.image, pageIndex = 0;

  final PageBackgroundKind kind;

  /// SHA-256 (lowercase hex) of the PDF file or image.
  final String blob;

  /// Zero-based page number within the PDF (0 for images).
  final int pageIndex;

  bool get isPdf => kind == PageBackgroundKind.pdf;

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  Map<String, Object?> toJson() => switch (kind) {
    PageBackgroundKind.pdf => {'type': 'pdf', 'blob': blob, 'page': pageIndex},
    PageBackgroundKind.image => {'type': 'image', 'blob': blob},
  };

  /// Parses a stored background; null if [json] is not a valid one.
  static PageBackground? fromJson(Object? json) {
    if (json is! Map) return null;
    final blob = json['blob'];
    if (blob is! String || !_sha256.hasMatch(blob)) return null;
    switch (json['type']) {
      case 'image':
        return PageBackground.image(blob: blob);
      case 'pdf':
        final page = json['page'];
        if (page is! int || page < 0) return null;
        return PageBackground.pdf(blob: blob, pageIndex: page);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PageBackground &&
      other.kind == kind &&
      other.blob == blob &&
      other.pageIndex == pageIndex;

  @override
  int get hashCode => Object.hash(kind, blob, pageIndex);
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

  /// The template (style and its parameters).
  final Paper paper;
  final PaperColor paperColor;
  final bool bookmarked;
  final PageBackground? background;

  /// [background] if it is a page of a PDF (text, links, outlines).
  PageBackground? get pdf => background != null && background!.isPdf ? background : null;

  /// The page area in world coordinates.
  Rect get bounds => Rect.fromLTWH(0, 0, width, height);

  Size get size => Size(width, height);

  /// This page's size with a new background of [shape] under it (another
  /// PDF page): its width kept, its height from [shape]'s aspect ratio, so
  /// its content stays where it is (anchored top left, nothing scaled).
  /// [size] when the shapes match (to a thousandth) or [shape] is empty.
  Size sizeFor(Size shape) {
    if (shape.isEmpty || width <= 0) return size;
    final height = width * shape.height / shape.width;
    return (height / this.height - 1).abs() < 1e-3 ? size : Size(width, height);
  }

  /// A template describing this page, for creating similar pages.
  PageTemplate get template {
    final match = PageFormat.match(size);
    return PageTemplate(
      paper: paper,
      color: paperColor,
      format: match?.format ?? PageFormat.a4,
      orientation:
          match?.orientation ??
          (width > height ? PageOrientation.landscape : PageOrientation.portrait),
      customSize: paper.style == PaperStyle.image ? size : null,
    );
  }

  NotebookPage copyWith({
    double? sortKey,
    Paper? paper,
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

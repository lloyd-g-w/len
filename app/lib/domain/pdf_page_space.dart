import 'dart:ui';

/// Maps rectangles of a PDF page's own coordinate space (points, y up,
/// before `/Rotate`) to the page as it is shown: normalised 0..1 from the
/// left and top edges of the displayed (rotated) page.
///
/// [left], [bottom], [right], [top] are relative to the lower-left corner
/// of the page's visible box, which is [width] × [height] points before
/// rotation; [quarterTurns] is `/Rotate` / 90 (clockwise when shown).
Rect pdfRectToDisplay(
  double left,
  double bottom,
  double right,
  double top, {
  required double width,
  required double height,
  required int quarterTurns,
}) {
  // Unrotated, normalised with a top-left origin.
  final a = Offset(left / width, 1 - top / height);
  final b = Offset(right / width, 1 - bottom / height);
  return Rect.fromPoints(rotateNormalized(a, quarterTurns), rotateNormalized(b, quarterTurns));
}

/// Turns the normalised point [p] (top-left origin) of a page clockwise by
/// [quarterTurns] quarter turns, staying normalised to the turned page.
Offset rotateNormalized(Offset p, int quarterTurns) => switch (quarterTurns % 4) {
  0 => p,
  1 => Offset(1 - p.dy, p.dx),
  2 => Offset(1 - p.dx, 1 - p.dy),
  _ => Offset(p.dy, 1 - p.dx),
};

/// A link on a PDF page: where it is and where it goes.
class PdfLinkArea {
  const PdfLinkArea(this.rects, {this.page, this.url});

  /// Its areas, normalised to the displayed page (0..1 from the left and
  /// top edges).
  final List<Rect> rects;

  /// The target page of the same PDF (zero-based), for internal links.
  final int? page;

  /// The target of external links.
  final Uri? url;

  bool contains(Offset normalized) => rects.any((r) => r.contains(normalized));

  @override
  String toString() => 'PdfLinkArea($rects, page: $page, url: $url)';
}

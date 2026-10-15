part of 'scan_session.dart';

/// One page of a scan being set up: the photo, the outline to flatten
/// and how far to turn the result.
class ScanPageDraft {
  ScanPageDraft(this.photo) : quad = photo.initialQuad;

  final ScanPhoto photo;

  /// The document's corners in photo pixels.
  Quad quad;

  /// Quarter turns clockwise of the flattened page (0..3).
  int turns = 0;

  /// The flattened page, small (for the page strip); null until rendered.
  ui.Image? preview;

  /// Width over height of the flattened page as the outline suggests (its
  /// top and left sides, turned): its shape until a preview is in.
  double get aspect {
    final w = (quad.topRight - quad.topLeft).distance,
        h = (quad.bottomLeft - quad.topLeft).distance;
    final a = h <= 0 || w <= 0 ? 1.0 : w / h;
    return turns.isOdd ? 1 / a : a;
  }

  /// Bumped on every change that the preview must follow.
  int _version = 0;
}

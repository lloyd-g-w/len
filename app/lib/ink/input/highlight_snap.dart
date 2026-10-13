import '../../domain/stroke.dart';

/// Text a highlighter stroke snaps to: PDF text in a paged editor.
abstract interface class HighlightSnap {
  /// Clean highlights replacing highlighter [stroke] (in its surface's
  /// coordinates), or null to keep it as drawn (it is not over text).
  List<Stroke>? snap(Stroke stroke);
}

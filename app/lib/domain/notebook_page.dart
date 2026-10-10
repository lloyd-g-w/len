import 'dart:ui';

import 'paper.dart';

/// One page of a paged notebook. Its [id] is the surface id of its strokes.
class NotebookPage {
  const NotebookPage({
    required this.id,
    required this.notebookId,
    required this.sortKey,
    required this.width,
    required this.height,
    required this.paper,
  });

  final String id;
  final String notebookId;

  /// Pages are ordered by ascending sort key. Fractional keys allow inserting
  /// between two pages without renumbering (and without sync conflicts).
  final double sortKey;

  final double width;
  final double height;
  final PaperStyle paper;

  /// The page area in world coordinates.
  Rect get bounds => Rect.fromLTWH(0, 0, width, height);
}

import 'dart:math' as math;

import '../../domain/stroke.dart';

/// Restacking ink: strokes paint in [Stroke.paintOrder] (when they were
/// drawn), so "Bring to front" and "Send to back" give the selected strokes
/// times just after or before the ink they overlap.
abstract final class StrokeOrder {
  /// New `createdAt`s (by stroke id) putting [selected] above ([front]) or
  /// beneath the strokes drawn at [others], keeping their own order; null
  /// when they are there already (or nothing else is near).
  static Map<String, int>? restacked(
    List<Stroke> selected,
    Iterable<int> others, {
    required bool front,
  }) {
    if (selected.isEmpty || others.isEmpty) return null;
    final ordered = [...selected]..sort(Stroke.paintOrder);
    final int base;
    if (front) {
      final top = others.reduce(math.max);
      if (ordered.first.createdAt > top) return null;
      base = top + 1;
    } else {
      final bottom = others.reduce(math.min);
      if (ordered.last.createdAt < bottom) return null;
      base = bottom - ordered.length;
    }
    return {for (var i = 0; i < ordered.length; i++) ordered[i].id: base + i};
  }
}

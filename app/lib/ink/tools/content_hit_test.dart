import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../stroke_hit_test.dart';
import '../surface_model.dart';

/// Finds what lies under a tap.
abstract final class ContentHitTest {
  /// The topmost element containing [world] (optionally only of [type], or
  /// only those [where] allows).
  static SurfaceElement? elementAt(
    SurfaceModel model,
    Offset world, {
    ElementType? type,
    bool Function(SurfaceElement element)? where,
  }) {
    final hits = model
        .elementsNear(Rect.fromCircle(center: world, radius: 1))
        .where((e) => (type == null || e.knownType == type) && (where?.call(e) ?? true))
        .where((e) => e.contains(world))
        .toList();
    if (hits.isEmpty) return null;
    hits.sort(SurfaceElement.paintOrder);
    return hits.last;
  }

  /// The topmost stroke within [tolerance] (world units) of [world];
  /// without [highlighter], highlighter strokes don't count; without [pen],
  /// pen strokes (and shapes) don't.
  static Stroke? strokeAt(
    SurfaceModel model,
    Offset world,
    double tolerance, {
    bool highlighter = true,
    bool pen = true,
  }) {
    final hits = model
        .strokesNear(Rect.fromCircle(center: world, radius: tolerance))
        .where((s) => s.tool.isHighlighter ? highlighter : pen)
        .where((s) => StrokeHitTest.sweepHits(s, world, world, tolerance))
        .toList();
    if (hits.isEmpty) return null;
    hits.sort(Stroke.paintOrder);
    return hits.last;
  }
}

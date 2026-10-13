import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../stroke_hit_test.dart';
import '../surface_model.dart';

/// Finds what lies under a tap.
abstract final class ContentHitTest {
  /// The topmost element containing [world] (optionally only of [type]).
  static SurfaceElement? elementAt(SurfaceModel model, Offset world, {ElementType? type}) {
    final hits = model
        .elementsNear(Rect.fromCircle(center: world, radius: 1))
        .where((e) => (type == null || e.knownType == type) && e.contains(world))
        .toList();
    if (hits.isEmpty) return null;
    hits.sort(SurfaceElement.paintOrder);
    return hits.last;
  }

  /// The topmost stroke within [tolerance] (world units) of [world];
  /// without [highlighter], highlighter strokes don't count.
  static Stroke? strokeAt(
    SurfaceModel model,
    Offset world,
    double tolerance, {
    bool highlighter = true,
  }) {
    final hits = model
        .strokesNear(Rect.fromCircle(center: world, radius: tolerance))
        .where((s) => highlighter || !s.tool.isHighlighter)
        .where((s) => StrokeHitTest.sweepHits(s, world, world, tolerance))
        .toList();
    if (hits.isEmpty) return null;
    hits.sort(Stroke.paintOrder);
    return hits.last;
  }
}

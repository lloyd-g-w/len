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
  /// pen strokes (and shapes) don't. A filled shape counts by its fill too,
  /// but ink whose line is hit wins over a translucent fill above it (a
  /// tint shows the ink through it); an opaque fill hides what is beneath.
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
    Stroke? tint;
    for (final s in hits.reversed) {
      if (StrokeHitTest.sweepHits(s, world, world, tolerance, fill: false)) return s;
      if ((s.fill ?? 0xFF000000) >>> 24 == 0xFF) return s;
      tint ??= s;
    }
    return tint;
  }
}

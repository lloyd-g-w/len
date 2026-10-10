import 'dart:math' as math;

import '../../domain/surface_element.dart';

/// Stacking orders ([SurfaceElement.z]) for new and restacked elements.
///
/// Elements with `z < 0` are drawn beneath the ink, the others above it
/// ([SurfaceElement.belowInk]). New text goes on top of everything; new
/// images go on top of the layer beneath the ink. "Bring to front" and
/// "send to back" move elements to the very top or bottom, which also
/// moves them above or beneath the ink.
abstract final class ElementOrder {
  /// The first element beneath the ink: far enough below zero that many
  /// more can be stacked above it with whole steps.
  static const double firstBelowInk = -1048576;

  /// Above every element (and the ink), given the current [top] z.
  static double onTop(double top) => math.max(top, 0.0) + 1;

  /// On top of the layer beneath the ink, given the highest z already in
  /// that layer ([topBelowInk], null if empty). Always negative.
  static double onTopBelowInk(double? topBelowInk) {
    if (topBelowInk == null) return firstBelowInk;
    return topBelowInk + 1 < 0 ? topBelowInk + 1 : topBelowInk / 2;
  }

  /// [elements] moved above everything, keeping their relative order.
  static List<SurfaceElement> toFront(List<SurfaceElement> elements, double top) {
    final ordered = [...elements]..sort(SurfaceElement.paintOrder);
    final base = onTop(top);
    return [for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(z: base + i)];
  }

  /// [elements] moved beneath everything (and the ink), keeping their
  /// relative order; [bottom] is the lowest z on the surface.
  static List<SurfaceElement> toBack(List<SurfaceElement> elements, double bottom) {
    final ordered = [...elements]..sort(SurfaceElement.paintOrder);
    final base = math.min(bottom, 0.0) - ordered.length;
    return [for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(z: base + i)];
  }

  /// Stacking orders for pasted copies of [ordered] (in paint order): each
  /// stays in its layer (beneath or above the ink) and lands on top of it.
  static List<double> pasted(
    List<SurfaceElement> ordered, {
    required double top,
    required double? topBelowInk,
  }) {
    var above = onTop(top);
    var below = topBelowInk;
    return [
      for (final e in ordered)
        if (e.belowInk) below = onTopBelowInk(below) else above++,
    ];
  }
}

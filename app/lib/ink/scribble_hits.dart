import 'dart:ui';

import '../domain/stroke.dart';
import '../domain/surface_element.dart';
import 'selection/lasso.dart';
import 'stroke_hit_test.dart';

/// What a scribble to erase takes: the strokes its zigzags cross (world
/// paths, within a radius) that lie mostly inside a zigzag's bounds, so a
/// long line under a scribbled word stays.
///
/// An outline the scribble fills in (a checkbox, a bullet) stays too: a
/// stroke whose bounds hold the zigzag's and which has no ink in the
/// zigzag's middle is something drawn around it, crossed only where the
/// passes turn.
abstract final class ScribbleHits {
  /// How far (its size ×) a zigzag may overshoot an outline it fills.
  static const double overshoot = 0.2;

  /// The share of a zigzag's points over text boxes or images (and not
  /// ink) for it to count as aimed at them.
  static const double onElements = 0.7;

  /// Where to look for the strokes of [paths] with [radius].
  static Rect area(List<Offset> path, double radius) => _bounds(path).inflate(radius);

  /// The strokes of [candidates] (those near [area] of a path) that the
  /// zigzag [path] takes.
  static Iterable<Stroke> taken(List<Offset> path, double radius, Iterable<Stroke> candidates) {
    if (path.length < 2) return const [];
    final bounds = _bounds(path);
    final area = bounds.inflate(radius);
    final box = Lasso([area.topLeft, area.topRight, area.bottomRight, area.bottomLeft]);
    final middle = Rect.fromCenter(
      center: bounds.center,
      width: bounds.width / 2,
      height: bounds.height / 2,
    );
    final core = Lasso([middle.topLeft, middle.topRight, middle.bottomRight, middle.bottomLeft]);
    bool crossed(Stroke stroke) {
      for (var i = 1; i < path.length; i++) {
        if (StrokeHitTest.sweepHits(stroke, path[i - 1], path[i], radius)) return true;
      }
      return false;
    }

    bool around(Stroke stroke) {
      final b = stroke.bounds;
      final reach = b.inflate(radius + overshoot * b.shortestSide);
      return reach.contains(bounds.topLeft) &&
          reach.contains(bounds.bottomRight) &&
          core.insideShare(stroke) == 0;
    }

    return candidates.where(
      (s) => box.insideShare(s) >= Lasso.strokeShare && crossed(s) && !around(s),
    );
  }

  /// Whether most of [paths] lies over [elements] (text boxes, images).
  static bool overElements(List<List<Offset>> paths, Iterable<SurfaceElement> elements) {
    final list = elements.toList();
    if (list.isEmpty) return false;
    var over = 0, total = 0;
    for (final path in paths) {
      for (final p in path) {
        total++;
        if (list.any((e) => e.contains(p))) over++;
      }
    }
    return total > 0 && over >= onElements * total;
  }

  static Rect _bounds(List<Offset> path) {
    var r = Rect.fromPoints(path.first, path.first);
    for (final p in path) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }
}

import 'dart:math' as math;
import 'dart:ui';

/// Polyline helpers for shape recognition.
abstract final class Polyline {
  /// [points] without consecutive duplicates.
  static List<Offset> dedupe(List<Offset> points) => [
    for (var i = 0; i < points.length; i++)
      if (i == 0 || points[i] != points[i - 1]) points[i],
  ];

  static double length(List<Offset> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
    }
    return total;
  }

  static Rect bounds(List<Offset> points) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static Offset centroid(List<Offset> points) =>
      points.reduce((a, b) => a + b) / points.length.toDouble();

  /// [n] points evenly spaced along [points] by arc length.
  static List<Offset> resample(List<Offset> points, int n) {
    final total = length(points);
    if (total == 0 || points.length < 2) return List.filled(n, points.first);
    final step = total / (n - 1);
    final out = [points.first];
    var carried = 0.0;
    for (var i = 1; i < points.length && out.length < n; i++) {
      var a = points[i - 1];
      final b = points[i];
      var segment = (b - a).distance;
      while (carried + segment >= step && out.length < n) {
        final t = (step - carried) / segment;
        a = Offset.lerp(a, b, t)!;
        out.add(a);
        segment = (b - a).distance;
        carried = 0;
      }
      carried += segment;
    }
    while (out.length < n) {
      out.add(points.last);
    }
    return out;
  }

  /// Cuts a closed-ish stroke where it comes back closest to its start
  /// (within its last third), dropping any overshoot past the start.
  static List<Offset> trimOverlap(List<Offset> points) {
    final total = length(points);
    var travelled = 0.0, best = points.length - 1;
    var bestDistance = double.infinity;
    for (var i = 1; i < points.length; i++) {
      travelled += (points[i] - points[i - 1]).distance;
      if (travelled < total * 2 / 3) continue;
      final d = (points[i] - points.first).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return points.sublist(0, best + 1);
  }

  /// Ramer–Douglas–Peucker simplification of an open polyline.
  static List<Offset> simplify(List<Offset> points, double epsilon) {
    if (points.length < 3) return List.of(points);
    final keep = List.filled(points.length, false)
      ..[0] = true
      ..[points.length - 1] = true;
    void recurse(int first, int last) {
      var maxDistance = 0.0, index = -1;
      for (var i = first + 1; i < last; i++) {
        final d = distanceToSegment(points[i], points[first], points[last]);
        if (d > maxDistance) {
          maxDistance = d;
          index = i;
        }
      }
      if (index != -1 && maxDistance > epsilon) {
        keep[index] = true;
        recurse(first, index);
        recurse(index, last);
      }
    }

    recurse(0, points.length - 1);
    return [
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }

  /// Corners of a closed loop (not repeating its start): RDP on both halves
  /// of the loop, then dropping vertices that barely turn (e.g. the start
  /// point when the shape was begun mid-edge) until all turn by > 30°, and
  /// one of any two closer than [merge] (a rounded corner taken as two).
  static List<Offset> corners(List<Offset> loop, double epsilon, {double merge = 0}) {
    var far = 0;
    for (var i = 1; i < loop.length; i++) {
      if ((loop[i] - loop[0]).distance > (loop[far] - loop[0]).distance) far = i;
    }
    if (far == 0) return const [];
    final first = simplify(loop.sublist(0, far + 1), epsilon);
    final second = simplify([...loop.sublist(far), loop.first], epsilon);
    final vertices = [...first, ...second.sublist(1, second.length - 1)];
    const minTurn = 30 * math.pi / 180;
    var changed = true;
    while (changed && vertices.length > 3) {
      changed = false;
      var weakest = -1, weakestTurn = minTurn;
      for (var i = 0; i < vertices.length; i++) {
        final turn = _turn(
          vertices[(i - 1 + vertices.length) % vertices.length],
          vertices[i],
          vertices[(i + 1) % vertices.length],
        );
        if (turn < weakestTurn) {
          weakestTurn = turn;
          weakest = i;
        }
      }
      if (weakest == -1) weakest = _crowded(vertices, merge);
      if (weakest != -1) {
        vertices.removeAt(weakest);
        changed = true;
      }
    }
    return vertices;
  }

  /// Of the closest two neighbouring [vertices], if closer than [merge],
  /// the one turning less; else -1.
  static int _crowded(List<Offset> vertices, double merge) {
    final n = vertices.length;
    var closest = -1, closestDistance = merge;
    for (var i = 0; i < n; i++) {
      final d = (vertices[(i + 1) % n] - vertices[i]).distance;
      if (d < closestDistance) {
        closestDistance = d;
        closest = i;
      }
    }
    if (closest == -1) return -1;
    double turn(int i) => _turn(vertices[(i - 1 + n) % n], vertices[i], vertices[(i + 1) % n]);
    final next = (closest + 1) % n;
    return turn(closest) < turn(next) ? closest : next;
  }

  /// [corners] of the closed [loop] moved to where its sides, fitted as
  /// straight lines, meet: a hand rounds corners off, cutting them short.
  /// Each side is fitted to the loop points nearest to it, leaving out
  /// those near its ends; a corner whose sides are nearly parallel, or
  /// that would move more than [reach], stays.
  static List<Offset> fitCorners(List<Offset> loop, List<Offset> corners, double reach) {
    final n = corners.length;
    final sides = List.generate(n, (_) => <Offset>[]);
    for (final p in loop) {
      var best = 0, bestDistance = double.infinity;
      for (var i = 0; i < n; i++) {
        final d = distanceToSegment(p, corners[i], corners[(i + 1) % n]);
        if (d < bestDistance) {
          bestDistance = d;
          best = i;
        }
      }
      final a = corners[best], b = corners[(best + 1) % n];
      final ab = b - a, lengthSq = ab.distanceSquared;
      if (lengthSq == 0) continue;
      final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSq;
      if (t > 0.2 && t < 0.8) sides[best].add(p);
    }
    final lines = [
      for (var i = 0; i < n; i++)
        sides[i].length >= 4 ? _fitLine(sides[i]) : (corners[i], corners[(i + 1) % n] - corners[i]),
    ];
    return [
      for (var i = 0; i < n; i++)
        () {
          final (p, u) = lines[(i - 1 + n) % n];
          final (q, v) = lines[i];
          final cross = u.dx * v.dy - u.dy * v.dx;
          if (cross.abs() < 0.2 * u.distance * v.distance) return corners[i];
          final t = ((q - p).dx * v.dy - (q - p).dy * v.dx) / cross;
          final meet = p + u * t;
          return (meet - corners[i]).distance <= reach ? meet : corners[i];
        }(),
    ];
  }

  /// The least-squares line through [points]: a point on it and its
  /// direction.
  static (Offset, Offset) _fitLine(List<Offset> points) {
    final c = centroid(points);
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final p in points) {
      final d = p - c;
      sxx += d.dx * d.dx;
      syy += d.dy * d.dy;
      sxy += d.dx * d.dy;
    }
    return (c, Offset.fromDirection(0.5 * math.atan2(2 * sxy, sxx - syy)));
  }

  /// Mean distance of [points] to the closed polygon [corners].
  static double meanDistanceToPolygon(List<Offset> points, List<Offset> corners) {
    var total = 0.0;
    for (final p in points) {
      var best = double.infinity;
      for (var i = 0; i < corners.length; i++) {
        best = math.min(best, distanceToSegment(p, corners[i], corners[(i + 1) % corners.length]));
      }
      total += best;
    }
    return total / points.length;
  }

  static double distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSq = ab.distanceSquared;
    if (lengthSq == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSq).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// Absolute change of direction at [b] (0 = straight on).
  static double _turn(Offset a, Offset b, Offset c) {
    final u = b - a, v = c - b;
    if (u.distance == 0 || v.distance == 0) return 0;
    final cross = u.dx * v.dy - u.dy * v.dx;
    final dot = u.dx * v.dx + u.dy * v.dy;
    return math.atan2(cross, dot).abs();
  }
}

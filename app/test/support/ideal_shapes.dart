import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/shape_kind.dart';

import 'hand_shapes.dart';

/// A shape to draw for hold to snap: its dense path and what it should
/// snap to.
typedef ShapeCase = ({String name, ShapeKind kind, List<Offset> path});

/// Ideal shapes about [size] across around [centre], turned by [angle]
/// where the kind allows it: exact geometry, closed exactly where they
/// began (mid-side), points about 2 apart.
List<ShapeCase> idealShapes(Offset centre, double size, {double angle = 0}) {
  List<Offset> turned(List<Offset> corners) => [
    for (final p in corners) centre + _rotate(p * size, angle),
  ];
  List<Offset> closed(List<Offset> c) {
    final mid = Offset.lerp(c[0], c[1], 0.5)!;
    return _dense([mid, ...c.skip(1), c[0], mid]);
  }

  List<Offset> oval(double rx, double ry) => [
    for (var i = 0, n = (math.pi * size / 2).ceil(); i <= n; i++)
      centre +
          _rotate(
            Offset(rx * math.cos(2 * math.pi * i / n), ry * math.sin(2 * math.pi * i / n)) * size,
            angle,
          ),
  ];

  final tip = centre + _rotate(Offset(size / 2, 0), angle);
  final tail = centre - _rotate(Offset(size / 2, 0), angle);
  final back = _rotate(Offset(-size * 0.2, 0), angle);
  return [
    (name: 'line', kind: ShapeKind.line, path: _dense([tail, tip])),
    (
      name: 'arrow',
      kind: ShapeKind.arrow,
      path: _dense([tail, tip, tip + _rotate(back, 0.5), tip, tip + _rotate(back, -0.5)]),
    ),
    (
      name: 'rectangle',
      kind: ShapeKind.rectangle,
      path: closed(
        turned(const [Offset(-.5, -.3), Offset(.5, -.3), Offset(.5, .3), Offset(-.5, .3)]),
      ),
    ),
    (
      name: 'square',
      kind: ShapeKind.rectangle,
      path: closed(
        turned(const [Offset(-.4, -.4), Offset(.4, -.4), Offset(.4, .4), Offset(-.4, .4)]),
      ),
    ),
    (
      name: 'triangle',
      kind: ShapeKind.triangle,
      path: closed(turned(const [Offset(0, -.45), Offset(.5, .4), Offset(-.5, .4)])),
    ),
    (
      name: 'diamond',
      kind: ShapeKind.diamond,
      path: closed([
        for (final p in const [Offset(0, -.5), Offset(.35, 0), Offset(0, .5), Offset(-.35, 0)])
          centre + p * size,
      ]),
    ),
    (name: 'ellipse', kind: ShapeKind.ellipse, path: oval(.5, .3)),
    (name: 'circle', kind: ShapeKind.circle, path: oval(.45, .45)),
    (name: 'pentagon', kind: ShapeKind.polygon, path: closed(turned(_regular(5)))),
    (name: 'hexagon', kind: ShapeKind.polygon, path: closed(turned(_regular(6)))),
  ];
}

/// A regular polygon with [n] corners, 1 across, one corner up.
List<Offset> _regular(int n) => [
  for (var i = 0; i < n; i++)
    Offset(math.sin(2 * math.pi * i / n), -math.cos(2 * math.pi * i / n)) * 0.5,
];

/// The same shapes as a hand draws them ([HandShapes], not sampled):
/// rounded corners, bowed sides, a gap or overshoot where they close.
List<ShapeCase> handShapes(Offset centre, double size, {double angle = 0, int seed = 1}) {
  final hand = HandShapes(seed, sampled: false);
  List<Offset> poly(List<Offset> corners, {double turn = 0}) =>
      hand.polygon([for (final p in corners) centre + p * size], angle: turn);
  final half = _rotate(Offset(size / 2, 0), angle);
  return [
    (name: 'line', kind: ShapeKind.line, path: hand.line(centre - half, centre + half)),
    (name: 'arrow', kind: ShapeKind.arrow, path: hand.arrow(centre - half, centre + half)),
    (
      name: 'rectangle',
      kind: ShapeKind.rectangle,
      path: poly(const [
        Offset(-.5, -.3),
        Offset(.5, -.3),
        Offset(.5, .3),
        Offset(-.5, .3),
      ], turn: angle),
    ),
    (
      name: 'square',
      kind: ShapeKind.rectangle,
      path: poly(const [
        Offset(-.4, -.4),
        Offset(.4, -.4),
        Offset(.4, .4),
        Offset(-.4, .4),
      ], turn: angle),
    ),
    (
      name: 'triangle',
      kind: ShapeKind.triangle,
      path: poly(const [Offset(0, -.45), Offset(.5, .4), Offset(-.5, .4)], turn: angle),
    ),
    (
      name: 'diamond',
      kind: ShapeKind.diamond,
      path: poly(const [Offset(0, -.5), Offset(.35, 0), Offset(0, .5), Offset(-.35, 0)]),
    ),
    (
      name: 'ellipse',
      kind: ShapeKind.ellipse,
      path: hand.ellipse(centre, size * .5, size * .3, angle: angle),
    ),
    (name: 'circle', kind: ShapeKind.circle, path: hand.ellipse(centre, size * .45, size * .45)),
    (name: 'pentagon', kind: ShapeKind.polygon, path: poly(_regular(5), turn: angle)),
    (name: 'hexagon', kind: ShapeKind.polygon, path: poly(_regular(6), turn: angle)),
  ];
}

/// [path] with points at most 2 apart.
List<Offset> _dense(List<Offset> path) => [
  path.first,
  for (var i = 1; i < path.length; i++)
    for (var k = 1, n = math.max(1, ((path[i] - path[i - 1]).distance / 2).ceil()); k <= n; k++)
      Offset.lerp(path[i - 1], path[i], k / n)!,
];

Offset _rotate(Offset v, double a) =>
    Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));

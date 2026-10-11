import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stickers/sticker.dart';
import '../../domain/stroke.dart';
import '../../ink/shapes/shape_builder.dart';
import '../../ink/shapes/shape_kind.dart';

/// The stickers that ship with Len: arrows, marks and callouts drawn as
/// clean vector ink (constant pressure, like shapes), so they recolour,
/// resize, erase and export like anything written by hand.
abstract final class BuiltinStickers {
  static const arrows = 'Arrows';
  static const marks = 'Marks';
  static const callouts = 'Callouts';

  /// Built-in categories, in the order the library shows them.
  static const categories = [arrows, marks, callouts];

  static const _ink = 0xFF1F2937, _blue = 0xFF3B5BDB, _red = 0xFFE03131;
  static const _green = 0xFF2F9E44, _amber = 0xFFF59F00, _pink = 0xFFD6336C;

  static final List<Sticker> all = [
    _s('arrow-right', 'Arrow', arrows, [
      _line(ShapeBuilder.arrow(const Offset(0, 30), const Offset(140, 30)), _ink),
    ]),
    _s('arrow-curved', 'Curved arrow', arrows, [
      _line(_curve(const Offset(0, 70), const Offset(60, -10), const Offset(130, 40)), _blue),
      _line(_head(const Offset(110, 22), const Offset(130, 40)), _blue),
    ]),
    _s('arrow-double', 'Double arrow', arrows, [
      _line(ShapeBuilder.arrow(const Offset(70, 30), const Offset(140, 30)), _ink),
      _line(ShapeBuilder.arrow(const Offset(70, 30), const Offset(0, 30)), _ink),
    ]),
    _s('arrow-down', 'Down arrow', arrows, [
      _line(ShapeBuilder.arrow(const Offset(30, 0), const Offset(30, 110)), _red, width: 5),
    ]),
    _s('check', 'Check mark', marks, [
      _line(const [Offset(0, 40), Offset(28, 68), Offset(90, 0)], _green, width: 7),
    ]),
    _s('cross', 'Cross', marks, [
      _line(const [Offset(0, 0), Offset(60, 60)], _red, width: 7),
      _line(const [Offset(60, 0), Offset(0, 60)], _red, width: 7),
    ]),
    _s('star', 'Star', marks, [
      _line(
        ShapeBuilder.outline(ShapeKind.star, Offset.zero, const Offset(90, 86)),
        _amber,
        width: 5,
      ),
    ]),
    _s('heart', 'Heart', marks, [_line(_heart(const Offset(50, 45), 46), _pink, width: 5)]),
    _s('circle', 'Circle', marks, [
      _line(ShapeBuilder.ellipse(const Offset(80, 40), 78, 38, angle: -0.06), _red, width: 4),
    ]),
    _s('underline', 'Squiggle', marks, [_line(_squiggle(160, 8, 6), _blue, width: 4)]),
    _s('speech', 'Speech bubble', callouts, [
      _line(_speech(const Rect.fromLTWH(0, 0, 160, 90)), _ink),
    ]),
    _s('thought', 'Thought bubble', callouts, [
      _line(ShapeBuilder.ellipse(const Offset(90, 45), 88, 44), _ink),
      _line(ShapeBuilder.ellipse(const Offset(28, 108), 11, 8), _ink),
      _line(ShapeBuilder.ellipse(const Offset(10, 128), 6, 5), _ink),
    ]),
    _s('note', 'Note box', callouts, [
      _line(_box(const Rect.fromLTWH(0, 0, 170, 100), 14), _blue),
      _line(const [Offset(12, 0), Offset(12, 100)], _blue, width: 6),
    ]),
    _s('important', 'Important', callouts, [
      _line(_box(const Rect.fromLTWH(0, 0, 60, 60), 30), _red, width: 5),
      _line(const [Offset(30, 12), Offset(30, 36)], _red, width: 7),
      _line(const [Offset(30, 46), Offset(30, 47)], _red, width: 8),
    ]),
  ];

  static Sticker _s(String id, String name, String category, List<Stroke> strokes) => Sticker(
    id: 'builtin:$id',
    name: name,
    category: category,
    content: StickerContent.normalized([for (final (i, s) in strokes.indexed) _at(s, i)], const []),
    createdAt: 0,
    builtIn: true,
  );

  static Stroke _at(Stroke s, int order) => Stroke(
    id: 's$order',
    surfaceId: '',
    tool: s.tool,
    color: s.color,
    width: s.width,
    points: s.points,
    createdAt: order,
    style: s.style,
  );

  static Stroke _line(List<Offset> vertices, int color, {double width = 4}) => Stroke(
    id: '',
    surfaceId: '',
    tool: InkTool.ballpoint,
    color: color,
    width: width,
    points: ShapeBuilder.points(vertices),
    createdAt: 0,
    style: ShapeBuilder.styleFor(StrokeStyle.defaultsFor(InkTool.ballpoint)),
  );

  /// A quadratic Bézier from [a] through control [c] to [b].
  static List<Offset> _curve(Offset a, Offset c, Offset b) => [
    for (var i = 0; i <= 40; i++)
      () {
        final t = i / 40;
        return a * ((1 - t) * (1 - t)) + c * (2 * t * (1 - t)) + b * (t * t);
      }(),
  ];

  /// The two wings of an arrow head arriving at [tip] from [from].
  static List<Offset> _head(Offset from, Offset tip) {
    final a = ShapeBuilder.arrow(from - (tip - from) * 3, tip);
    return [a[2], a[3], a[4]];
  }

  static List<Offset> _heart(Offset c, double r) => [
    for (var i = 0; i <= 120; i++)
      () {
        final t = 2 * math.pi * i / 120;
        final x = 16 * math.pow(math.sin(t), 3).toDouble();
        final y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t);
        return c + Offset(x, -y) * (r / 17);
      }(),
  ];

  static List<Offset> _squiggle(double length, double amplitude, int waves) => [
    for (var i = 0; i <= waves * 16; i++)
      Offset(length * i / (waves * 16), amplitude * math.sin(i / 16 * 2 * math.pi)),
  ];

  /// A rounded rectangle traced clockwise from the top-left corner's end.
  static List<Offset> _box(Rect r, double radius) {
    final pts = <Offset>[];
    void arc(Offset centre, double from) {
      for (var i = 0; i <= 8; i++) {
        pts.add(centre + Offset.fromDirection(from + math.pi / 2 * i / 8, radius));
      }
    }

    arc(r.topRight + Offset(-radius, radius), -math.pi / 2);
    arc(r.bottomRight + Offset(-radius, -radius), 0);
    arc(r.bottomLeft + Offset(radius, -radius), math.pi / 2);
    arc(r.topLeft + Offset(radius, radius), math.pi);
    return [...pts, pts.first];
  }

  /// A rounded box with a tail at its bottom left.
  static List<Offset> _speech(Rect r) {
    final box = _box(r, 18);
    // Cut the bottom edge open (between the bottom corners) for the tail.
    final i = box.indexWhere((p) => p.dy >= r.bottom - 0.01 && p.dx < r.left + 40);
    return [
      ...box.sublist(0, i),
      Offset(r.left + 56, r.bottom),
      Offset(r.left + 20, r.bottom + 34),
      Offset(r.left + 36, r.bottom),
      ...box.sublist(i),
    ];
  }
}

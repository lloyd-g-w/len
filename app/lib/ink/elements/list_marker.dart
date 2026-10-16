import 'dart:ui';

import '../../domain/text/text_data.dart';

/// The bullet, number or checkbox in front of a list paragraph of a text
/// box. It occupies an inline placeholder at the start of the line (the
/// right edge of a right-to-left paragraph), so the text field used for
/// editing and every renderer lay it out identically; [shapes] describes
/// what to draw in that box (for the canvas and PDF).
class ListMarker {
  const ListMarker({
    required this.line,
    required this.para,
    required this.number,
    required this.fontSize,
    required this.color,
    required this.font,
    this.continued = false,
    this.direction = TextDirection.ltr,
  });

  /// The paragraph (line) it belongs to.
  final int line;
  final ParaStyle para;

  /// Position in a numbered list (1-based).
  final int number;

  /// Size of the line's text, in world units.
  final double fontSize;

  /// ARGB colour of the line's text.
  final int color;

  /// Font of the line's text (for numbers).
  final TextFont font;

  /// Whether the item began in the box before (a box continuing on the
  /// next page, `TextFlow.joined`): its line keeps the marker's room (it
  /// hangs under the item's text) but shows no marker.
  final bool continued;

  /// The paragraph's direction: the marker column is on its text side.
  final TextDirection direction;

  bool get _rtl => direction == TextDirection.rtl;

  /// Width of one indent level (and of the marker column), in ems.
  static const double indentEms = 1.6;

  /// Size of the placeholder.
  Size get size => Size(fontSize * indentEms * (para.indent + 1), fontSize);

  /// The label of a numbered item (`1.`, `a.`, `i.` by level).
  String get label => '${_counter(number, para.indent % 3)}.';

  static String _counter(int n, int style) => switch (style) {
    1 => _letters(n),
    2 => _roman(n),
    _ => '$n',
  };

  static String _letters(int n) {
    var s = '';
    for (var k = n; k > 0; k = (k - 1) ~/ 26) {
      s = String.fromCharCode(0x61 + (k - 1) % 26) + s;
    }
    return s;
  }

  static String _roman(int n) {
    if (n <= 0 || n >= 4000) return '$n';
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const glyphs = ['m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i'];
    final out = StringBuffer();
    var k = n;
    for (var i = 0; i < values.length; i++) {
      while (k >= values[i]) {
        out.write(glyphs[i]);
        k -= values[i];
      }
    }
    return out.toString();
  }

  /// The marker column: the [indentEms] of [box] (the placeholder) next
  /// to the text, its end in the paragraph's direction.
  Rect column(Rect box) => _rtl
      ? Rect.fromLTRB(box.left, box.top, box.left + fontSize * indentEms, box.bottom)
      : Rect.fromLTRB(box.right - fontSize * indentEms, box.top, box.right, box.bottom);

  /// The centre of a bullet or checkbox in [box]: away from the text.
  Offset _centre(Rect box) {
    final c = column(box);
    final inset = fontSize * 0.55;
    return Offset(_rtl ? c.right - inset : c.left + inset, box.center.dy);
  }

  /// The tick box of a checklist item placed in [box].
  Rect checkbox(Rect box) {
    final side = fontSize * 0.72;
    return Rect.fromCenter(center: _centre(box), width: side, height: side);
  }

  /// What to draw for a bullet or checkbox in [box] (numbers are text).
  List<MarkerShape> shapes(Rect box) {
    final centre = _centre(box);
    switch (para.list) {
      case ListKind.bullet:
        final r = fontSize * 0.14;
        return switch (para.indent % 3) {
          0 => [MarkerShape.disc(Rect.fromCircle(center: centre, radius: r))],
          1 => [MarkerShape.ring(Rect.fromCircle(center: centre, radius: r), fontSize * 0.07)],
          _ => [MarkerShape.square(Rect.fromCircle(center: centre, radius: r * 0.9))],
        };
      case ListKind.check:
        final b = checkbox(box);
        final stroke = fontSize * 0.08;
        if (!para.checked) return [MarkerShape.box(b, stroke)];
        return [
          MarkerShape.filledBox(b),
          MarkerShape.tick([
            Offset(b.left + b.width * 0.22, b.top + b.height * 0.52),
            Offset(b.left + b.width * 0.42, b.top + b.height * 0.72),
            Offset(b.left + b.width * 0.78, b.top + b.height * 0.3),
          ], stroke * 1.3),
        ];
      case ListKind.number || ListKind.none:
        return const [];
    }
  }

  /// Paints the marker into [box] on [canvas]; [number] lays out and paints
  /// a numbered item's label (text belongs to the caller's text stack).
  void paint(Canvas canvas, Rect box, {void Function(String label, Rect column)? number}) {
    if (para.list == ListKind.number) {
      number?.call(label, column(box));
      return;
    }
    final ink = Paint()
      ..color = Color(color)
      ..isAntiAlias = true;
    for (final s in shapes(box)) {
      switch (s.kind) {
        case MarkerShapeKind.disc:
          canvas.drawOval(s.rect, ink);
        case MarkerShapeKind.ring:
          canvas.drawOval(s.rect.deflate(s.stroke / 2), _stroke(ink, s.stroke));
        case MarkerShapeKind.square:
          canvas.drawRect(s.rect, ink);
        case MarkerShapeKind.box:
          canvas.drawRRect(s.rrect.deflate(s.stroke / 2), _stroke(ink, s.stroke));
        case MarkerShapeKind.filledBox:
          canvas.drawRRect(s.rrect, ink);
        case MarkerShapeKind.tick:
          final path = Path()..addPolygon(s.points, false);
          canvas.drawPath(
            path,
            _stroke(Paint()..color = const Color(0xFFFFFFFF), s.stroke)
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ListMarker &&
      other.line == line &&
      other.para == para &&
      other.number == number &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.font == font &&
      other.direction == direction &&
      other.continued == continued;

  @override
  int get hashCode => Object.hash(line, para, number, fontSize, color, font, direction, continued);

  static Paint _stroke(Paint base, double width) => Paint()
    ..color = base.color
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
}

enum MarkerShapeKind { disc, ring, square, box, filledBox, tick }

/// One primitive of a list marker, in world units.
class MarkerShape {
  const MarkerShape._(this.kind, this.rect, {this.stroke = 0, this.points = const []});

  MarkerShape.disc(Rect rect) : this._(MarkerShapeKind.disc, rect);
  MarkerShape.ring(Rect rect, double stroke) : this._(MarkerShapeKind.ring, rect, stroke: stroke);
  MarkerShape.square(Rect rect) : this._(MarkerShapeKind.square, rect);
  MarkerShape.box(Rect rect, double stroke) : this._(MarkerShapeKind.box, rect, stroke: stroke);
  MarkerShape.filledBox(Rect rect) : this._(MarkerShapeKind.filledBox, rect);
  MarkerShape.tick(List<Offset> points, double stroke)
    : this._(MarkerShapeKind.tick, Rect.zero, stroke: stroke, points: points);

  final MarkerShapeKind kind;
  final Rect rect;
  final double stroke;
  final List<Offset> points;

  /// Corner radius of checkboxes.
  double get radius => rect.width * 0.2;
  RRect get rrect => RRect.fromRectAndRadius(rect, Radius.circular(radius));
}

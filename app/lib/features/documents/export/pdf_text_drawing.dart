part of 'pdf_text.dart';

/// Drawing laid-out text: highlights, glyphs, decorations and list markers.
extension _PdfTextDrawing on PdfTextWriter {
  static void _fill(PdfGraphics g, Color c) {
    g
      ..setFillColor(PdfColor.fromInt(c.toARGB32() | 0xFF000000))
      ..setGraphicState(PdfGraphicState(fillOpacity: c.a));
  }

  void _highlight(PdfGraphics g, _Run r) {
    final paint = r.style.background;
    if (paint == null) return;
    _fill(g, paint.color);
    for (final b in r.boxes) {
      g.drawRect(b.left, b.top, b.width, b.height);
    }
    g.fillPath();
  }

  void _text(PdfGraphics g, _Run r) {
    if (r.words.isEmpty) return;
    _fill(g, r.style.color!);
    final size = r.style.fontSize!;
    for (final w in r.words) {
      final glyph = Matrix4.identity()
        ..translateByDouble(w.x, w.baseline, 0, 1)
        ..scaleByDouble(1, -1, 1, 1);
      if (w.slant) glyph.setEntry(0, 1, PdfTextWriter._slant);
      g
        ..saveContext()
        ..setTransform(glyph)
        ..drawString(w.font, size, w.text, 0, 0)
        ..restoreContext();
    }
  }

  void _decorations(PdfGraphics g, _Run r) {
    final deco = r.style.decoration;
    if (deco == null || deco == TextDecoration.none || r.words.isEmpty) return;
    final size = r.style.fontSize!;
    final thickness = math.max(size * 0.05, 0.5);
    _fill(g, r.style.decorationColor ?? r.style.color!);
    final baselines = {for (final w in r.words) w.baseline};
    for (final b in r.boxes) {
      final baseline = baselines.firstWhere(
        (y) => y > b.top && y <= b.bottom,
        orElse: () => b.bottom - size * 0.25,
      );
      if (deco.contains(TextDecoration.underline)) {
        g.drawRect(b.left, baseline + size * 0.1, b.width, thickness);
      }
      if (deco.contains(TextDecoration.lineThrough)) {
        g.drawRect(b.left, baseline - size * 0.3, b.width, thickness);
      }
    }
    g.fillPath();
  }

  Future<void> _markers(PdfGraphics g, TextBoxLayout layout) async {
    final boxes = layout.markerBoxes;
    for (var i = 0; i < layout.markers.length && i < boxes.length; i++) {
      final m = layout.markers[i];
      if (m.para.list == ListKind.number) {
        await _number(g, m, boxes[i]);
      } else {
        _shapes(g, m, m.shapes(boxes[i]));
      }
    }
  }

  Future<void> _number(PdfGraphics g, ListMarker m, Rect box) async {
    final label = m.label;
    final p = TextBoxLayout.numberPainter(m, label);
    final origin = TextBoxLayout.numberOrigin(m, p, m.column(box));
    final baseline = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    p.dispose();
    final font = await this.font(m.font, bold: false, italic: false);
    _fill(g, Color(m.color));
    g
      ..saveContext()
      ..setTransform(
        Matrix4.identity()
          ..translateByDouble(origin.dx, origin.dy + baseline, 0, 1)
          ..scaleByDouble(1, -1, 1, 1),
      )
      ..drawString(font, m.fontSize, _visual(m, label), 0, 0)
      ..restoreContext();
  }

  /// [label] ("12.") in visual order: its full stop goes left of the
  /// number in a right-to-left paragraph (".12"), as the canvas shows it.
  static String _visual(ListMarker m, String label) =>
      m.direction == TextDirection.rtl ? '.${label.substring(0, label.length - 1)}' : label;

  void _shapes(PdfGraphics g, ListMarker m, List<MarkerShape> shapes) {
    final ink = PdfColor.fromInt(m.color | 0xFF000000);
    g
      ..setFillColor(ink)
      ..setStrokeColor(ink)
      ..setGraphicState(
        PdfGraphicState(fillOpacity: Color(m.color).a, strokeOpacity: Color(m.color).a),
      );
    for (final s in shapes) {
      final r = s.rect;
      switch (s.kind) {
        case MarkerShapeKind.disc:
          g
            ..drawEllipse(r.center.dx, r.center.dy, r.width / 2, r.height / 2)
            ..fillPath();
        case MarkerShapeKind.ring:
          g
            ..setLineWidth(s.stroke)
            ..drawEllipse(
              r.center.dx,
              r.center.dy,
              (r.width - s.stroke) / 2,
              (r.height - s.stroke) / 2,
            )
            ..strokePath();
        case MarkerShapeKind.square:
          g
            ..drawRect(r.left, r.top, r.width, r.height)
            ..fillPath();
        case MarkerShapeKind.box:
          final d = r.deflate(s.stroke / 2);
          g
            ..setLineWidth(s.stroke)
            ..drawRRect(d.left, d.top, d.width, d.height, s.radius, s.radius)
            ..strokePath();
        case MarkerShapeKind.filledBox:
          g
            ..drawRRect(r.left, r.top, r.width, r.height, s.radius, s.radius)
            ..fillPath();
        case MarkerShapeKind.tick:
          g
            ..saveContext()
            ..setStrokeColor(PdfColors.white)
            ..setLineWidth(s.stroke)
            ..setLineCap(PdfLineCap.round)
            ..setLineJoin(PdfLineJoin.round)
            ..moveTo(s.points.first.dx, s.points.first.dy);
          for (final p in s.points.skip(1)) {
            g.lineTo(p.dx, p.dy);
          }
          g
            ..strokePath()
            ..restoreContext();
      }
    }
  }
}

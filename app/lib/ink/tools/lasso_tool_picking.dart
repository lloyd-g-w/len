part of 'lasso_tool.dart';

/// What a press, tap or loop of the lasso picks: hit tests by the gesture's
/// [LassoConfig], taps (a second one on a text box edits it), loops, and
/// where a dragged shape point goes.
extension _LassoPicking on LassoTool {
  /// Where a dragged shape point goes for the pointer at [world]. With
  /// Shift, a line's or arrow's end keeps to 15° steps around the other,
  /// and a rectangle's or ellipse's corner to its diagonal (proportions
  /// kept); without, they snap when nearly level or square ([ShapeSnap]).
  Offset _reshapeTarget(Offset world) {
    final shape = _shape!;
    if (!HardwareKeyboard.instance.isShiftPressed) return _snapTarget(shape, world);
    switch (shape.kind) {
      case ShapeKind.line || ShapeKind.arrow:
        return ShapeTool.constrain(shape.kind, shape.points[1 - _point], world);
      case ShapeKind.rectangle || ShapeKind.ellipse:
        final corners = ShapeHandles.of(shape);
        final opposite = corners[(_point + 2) % 4], diagonal = corners[_point] - opposite;
        final d = world - opposite;
        final t = (d.dx * diagonal.dx + d.dy * diagonal.dy) / diagonal.distanceSquared;
        return diagonal == Offset.zero ? world : opposite + diagonal * t;
      case ShapeKind.triangle || ShapeKind.diamond || ShapeKind.polygon || ShapeKind.star:
        return world;
    }
  }

  /// [world] snapped for a dragged point of [shape] without Shift: a
  /// line's end nearly level, upright or diagonal, a rectangle's or
  /// ellipse's corner nearly square.
  Offset _snapTarget(ShapeGeometry shape, Offset world) {
    switch (shape.kind) {
      case ShapeKind.line || ShapeKind.arrow:
        return ShapeSnap.lineEnd(shape.points[1 - _point], world);
      case ShapeKind.rectangle || ShapeKind.ellipse:
        if (_point > 3) return world;
        final opposite = ShapeHandles.of(shape)[(_point + 2) % 4];
        return ShapeSnap.squareCorner(opposite, world, ShapeHandles.angleOf(shape));
      case ShapeKind.triangle || ShapeKind.diamond || ShapeKind.polygon || ShapeKind.star:
        return world;
    }
  }

  /// Whether ink or an element the lasso takes lies under [world].
  /// Highlights don't count: highlighted PDF text stays selectable (a lasso
  /// loop still takes them).
  bool _hitsContent(Offset world) =>
      _elementAt(world) != null || _strokeAt(world, highlighter: false) != null;

  /// The topmost element of a kind the lasso takes under [world].
  SurfaceElement? _elementAt(Offset world) => ContentHitTest.elementAt(
    selection.model,
    world,
    where: (e) =>
        _options.takes(e.knownType == ElementType.text ? LassoKind.text : LassoKind.images),
  );

  /// The topmost stroke of a kind the lasso takes under [world].
  Stroke? _strokeAt(Offset world, {bool highlighter = true}) => ContentHitTest.strokeAt(
    selection.model,
    world,
    8 / viewport.scale,
    pen: _options.takes(LassoKind.ink),
    highlighter: highlighter && _options.takes(LassoKind.highlighter),
  );

  /// A tap on text: its word, and the ink selection goes.
  void _tapText() {
    _lastTap = null;
    selection.clear();
    text!.selectWordAt(_startScreen);
  }

  /// Whether the lasso path came back near its start (a loop): its ends are
  /// closer than half its extent. An open drag over text selects text, and
  /// so does a rectangle.
  bool get _closed {
    if (_options.shape == LassoShape.rectangle) return false;
    final points = path.points;
    if (points.length < 3) return false;
    final bounds = Rect.fromPoints(points.first, points.first);
    final extent = points.fold(bounds, (r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
    return (points.last - points.first).distance < extent.longestSide / 2;
  }

  void _selectLasso() {
    final lasso = Lasso([...path.points], config: _options);
    if (!lasso.isValid) {
      selection.clear();
      return;
    }
    selection.selectLasso(lasso);
  }

  /// Selects what is under a tap; a second tap on a text box edits it.
  void _tap(Offset world, {bool keepSelection = false}) {
    var element = _elementAt(world);
    // Ink lies above elements beneath it: a tap on that ink selects the ink.
    if (element != null && element.belowInk && !keepSelection) {
      if (_strokeAt(world) != null) element = null;
    }
    final now = _now();
    if (element != null) {
      final last = _lastTap;
      _lastTap = (id: element.id, time: now);
      if (last != null &&
          last.id == element.id &&
          now - last.time <= LassoTool.doubleTapMs &&
          element.knownType == ElementType.text) {
        _lastTap = null;
        selection.clear();
        onEditText?.call(element);
        return;
      }
      if (!keepSelection) selection.select(const [], [element]);
      return;
    }
    _lastTap = null;
    if (keepSelection) return;
    final stroke = _strokeAt(world);
    if (stroke != null) {
      selection.select([stroke], const []);
    } else {
      selection.clear();
    }
  }
}

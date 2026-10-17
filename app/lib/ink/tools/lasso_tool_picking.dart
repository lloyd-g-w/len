part of 'lasso_tool.dart';

/// What a press, tap or loop of the lasso picks: hit tests by the gesture's
/// [LassoConfig], taps (a second one on a text box edits it, on a curve's
/// anchor removes it; one on a curve's line adds an anchor), and loops.
extension _LassoPicking on LassoTool {
  /// A tap on handle [_point] of [_shape]: the second of a double tap on a
  /// curve's anchor removes it (a curve keeps two at least).
  void _tapHandle() {
    final shape = _shape!, now = _now();
    final last = _lastHandleTap;
    _lastHandleTap = (point: _point, time: now);
    if (shape.kind != ShapeKind.curve || _point % 3 != 0 || shape.anchorCount <= 2) return;
    if (last == null || last.point != _point || now - last.time > LassoTool.doubleTapMs) return;
    _lastHandleTap = null;
    final closed = shape.isClosed;
    selection
      ..reshape(shape.withPoints(Bezier.removeAnchor(shape.points, _point ~/ 3, closed: closed)))
      ..commitReshape();
  }

  /// A tap at [world] on the line of a selected curve adds an anchor there
  /// (the outline stays as it was). Returns whether it did.
  bool _addAnchor(Offset world) {
    final shape = selection.shape;
    if (shape == null || shape.kind != ShapeKind.curve) return false;
    if (shape.anchorCount >= ShapeGeometry.maxAnchors) return false;
    final closed = shape.isClosed;
    final hit = Bezier.nearest(shape.points, world, closed: closed);
    if (hit.distance * viewport.scale > SelectionChrome.hitRadius) return false;
    selection
      ..reshape(shape.withPoints(Bezier.split(shape.points, hit.segment, hit.t, closed: closed)))
      ..commitReshape();
    return true;
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

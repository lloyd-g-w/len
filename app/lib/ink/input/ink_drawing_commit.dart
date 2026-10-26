part of 'ink_drawing.dart';

/// Committing the ink of a contact that ended: the stroke, a snapped
/// highlight, the shape hint and the bounce check.
extension _InkCommit on InkDrawing {
  void _commit(
    List<StrokePoint> points,
    Duration? liftTime, {
    required bool snapped,
    ShapeGeometry? shape,
  }) {
    if (kind == PointerDeviceKind.touch) events.fingerStroke?.call();
    // Its chunks and bounds were traced as it was drawn.
    final trace = _chunks;
    final traced =
        trace != null &&
        _chunksGeneration == live.generation &&
        trace.width == live.width &&
        trace.follows(points);
    final chunks = traced ? trace.finish(points) : null;
    final stroke = Stroke(
      id: clock.newId(),
      surfaceId: model.surfaceId,
      tool: live.tool,
      color: live.color,
      width: live.width,
      style: _endFollowsSpeed
          ? live.style.copyWith(taperEnd: live.style.taperEnd * _liftSpeed.scale)
          : live.style,
      points: points,
      createdAt: _drawStartedAt,
      shape: shape,
      bounds: traced ? trace.bounds : null,
    );
    // Over PDF text, a highlight snaps to the words it covers (no hold
    // needed) unless the highlighter's Snap to text is off.
    if (stroke.tool.isHighlighter && tools.configOf(stroke.tool).snapToText) {
      if (highlightSnap?.snap(stroke) case final snapped? when snapped.isNotEmpty) {
        _committedIds = [for (final s in snapped) s.id];
        return model.commit(InkEdit(added: snapped));
      }
    }
    if (!snapped) _hintShape(stroke);
    // The live outline's builder completes it (cheaply) at pen-up.
    final path = LiveStrokeBuilder.finishLive(
      live,
      points,
      width: stroke.width,
      style: stroke.style,
    );
    if (path != null) StrokeRenderer.adopt(stroke, path);
    if (chunks != null && stroke.fill == null) StrokeChunks.adopt(stroke, chunks);
    _committed = stroke;
    PerfProbe.lift(liftTime);
    developer.Timeline.timeSync('len.commitStroke', () => model.addStroke(stroke));
  }

  /// Tells [events] about a line or shape drawn without hold to snap (only
  /// while someone listens: the recogniser isn't free).
  void _hintShape(Stroke stroke) {
    final hint = events.shapeDrawn;
    if (hint == null || !tools.holdToStraighten || stroke.tool != InkTool.ballpoint) return;
    // At most a few hundred points (a hint, not a snap): a long stroke's
    // all would make pen-up cost its length.
    final points = stroke.points;
    final step = (points.length / _hintPoints).ceil();
    final offsets = [
      for (var i = 0; i < points.length; i += step) points[i].offset,
      if ((points.length - 1) % step != 0) points.last.offset,
    ];
    if (HoldToStraighten.wouldSnap(offsets, viewport.scale)) hint();
  }

  /// The most points [_hintShape] looks at.
  static const int _hintPoints = 512;

  /// Whether the contact that just ended was an accidental stylus bounce.
  bool _isBounce(Duration? liftTime) =>
      liftTime != null &&
      byStylus &&
      _bounces.isBounce(
        down: _drawStartTime,
        up: liftTime,
        start: _drawStartScreen,
        travel: _drawTravel,
      );

  void _recordLift(Duration? liftTime) {
    // Where the pen lifted: a bounce lands there, not where the
    // stabiliser's ink stopped (up to its string short of the pen).
    final at = _stabiliser?.pen ?? _lastScreen;
    if (liftTime != null && byStylus && at != null) _bounces.recordLift(liftTime, at);
  }
}

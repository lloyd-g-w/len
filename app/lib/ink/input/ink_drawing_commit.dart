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
    );
    // Over PDF text, a highlight snaps to the words it covers (always: no
    // hold needed).
    if (stroke.tool.isHighlighter) {
      if (highlightSnap?.snap(stroke) case final snapped? when snapped.isNotEmpty) {
        return model.commit(InkEdit(added: snapped));
      }
    }
    if (!snapped) _hintShape(stroke);
    // The live outline's builder completes it (cheaply) at pen-up.
    final path = LiveStrokeBuilder.finishLive(
      live,
      points,
      tool: stroke.tool,
      width: stroke.width,
      style: stroke.style,
    );
    if (path != null) StrokeRenderer.adopt(stroke, path);
    _committedTaper = StrokeRenderer.specFor(stroke.tool, stroke.width, stroke.style).taperEnd;
    PerfProbe.lift(liftTime);
    developer.Timeline.timeSync('len.commitStroke', () => model.addStroke(stroke));
  }

  /// Tells [events] about a line or shape drawn without hold to snap (only
  /// while someone listens: the recogniser isn't free).
  void _hintShape(Stroke stroke) {
    final hint = events.shapeDrawn;
    if (hint == null || !tools.holdToStraighten || stroke.tool != InkTool.ballpoint) return;
    if (HoldToStraighten.wouldSnap([for (final p in stroke.points) p.offset], viewport.scale)) {
      hint();
    }
  }

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
    if (liftTime != null && byStylus && _lastScreen != null) {
      _bounces.recordLift(liftTime, _lastScreen!);
    }
  }
}

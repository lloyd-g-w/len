part of 'live_stroke.dart';

/// What the last live frame showed of a stroke whose live line ended
/// before its newest samples (the stabiliser on): its frozen part, and its
/// tail from sample [from] to [end] (a cap at each), with the samples near
/// [end] and the corners before it, to tell whether the committed line
/// still agrees there.
class _Shown {
  _Shown(this.frozen, this.from, this.end, StrokeShaper s)
    : corners = [
        for (final c in s.corners)
          if (c < end) c,
      ],
      values = [
        for (var i = math.max(0, end - _checked); i <= end; i++) ...[s.x[i], s.y[i], s.r[i]],
      ];

  static const int _checked = 8;

  final Path frozen;
  final int from;
  final int end;
  final List<int> corners;
  final List<double> values;

  /// Whether the line of [s] is the one shown up to [end], and goes on.
  bool agrees(StrokeShaper s) {
    if (s.length <= end + 1) return false;
    if (!listEquals(corners, [
      for (final c in s.corners)
        if (c < end) c,
    ])) {
      return false;
    }
    var k = 0;
    for (var i = math.max(0, end - _checked); i <= end; i++) {
      if (s.x[i] != values[k++] || s.y[i] != values[k++] || s.r[i] != values[k++]) return false;
    }
    return true;
  }
}

/// The hand-over at pen-up with the stabiliser on.
extension _Handover on LiveStrokeBuilder {
  /// The committed outline of the ended line as the last frame [shown]
  /// drew it, and the rest of the line from where that frame's line ended;
  /// null when the line changed there (an end taper reaching back into
  /// it, changed input).
  ///
  /// The outline is the same area as rebuilt, but every edge the last
  /// frame drew is drawn again, the same curves. Rebuilt, the cubics
  /// fitted to the sides over the shown tail's last stretch differ (that
  /// frame fitted them up to where its line ended), and an outline of the
  /// same area but other curves is rasterised a little differently: edge
  /// pixels there changed shade at pen-up (by up to a quarter, at 110 %).
  Path? _handOver(_Shown? shown) {
    if (shown == null) return null;
    final end = shown.end;
    if (_shaper.taperedFrom <= end + 1 || !shown.agrees(_shaper)) return null;
    final prefix = RibbonEmitter(
      RibbonPrefix(_shaper, end + 1),
      flatCaps: false,
      width: spec.width,
      step: _shaper.p.step,
      lookahead: 1,
    );
    final join = prefix.endJoin();
    // The frozen part copied (a block copy), the rest after it.
    final out = Path.from(shown.frozen);
    final sink = PathSink(out);
    if (join != null && _emitter.continuesAt(join)) {
      // Cut where it ended, and continued edge to edge from the cut.
      prefix.emitCut(sink, from: (at: shown.from, cut: false));
      _emitter.emitJoined(sink, join);
    } else {
      // A corner or fold there: the shown outline whole, its end's cap
      // too, and the rest from a cap on the same circle (the union of the
      // circles all the same).
      prefix.emit(sink, from: (at: shown.from, cut: false));
      _emitter.emit(sink, from: (at: end, cut: false));
    }
    return out;
  }
}

/// The first sample's dot, all the last frame showed of a line (the
/// stabiliser on, nothing of it final yet: no frozen part to hand over).
class _Dot {
  _Dot(StrokeShaper s, this.path) : x = s.x[0], y = s.y[0], r = s.r[0];

  final double x, y, r;
  final Path path;

  /// The committed outline of [points]: rebuilt (nothing was final), and
  /// with the dot's own circle when the stroke's start still covers it,
  /// so its edge is drawn as before (the start's cap is the same circle,
  /// or a larger one, drawn with other curves).
  Path finish(List<StrokePoint> points, OutlineSpec spec) {
    final shaper = StrokeOutline.shaperOf(points, spec);
    final out = Path();
    if (shaper.inputCount == 0) return out;
    StrokeOutline.emitLine(PathSink(out), shaper, spec);
    if (!StrokeOutline.isDot(shaper) && shaper.x[0] == x && shaper.y[0] == y && shaper.r[0] >= r) {
      out.addPath(path, Offset.zero);
    }
    return out;
  }
}

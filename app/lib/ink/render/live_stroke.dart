import 'dart:ui';

import '../../domain/stroke.dart';
import '../pen/pen_profile.dart';
import 'outline_sink.dart';
import 'ribbon_emitter.dart';
import 'stroke_outline.dart';
import 'stroke_renderer.dart';
import 'stroke_shaper.dart';

/// Builds the outline of the stroke being drawn, frame by frame, in
/// constant time per frame.
///
/// The part of the outline that can no longer change (everything a few
/// pen-widths behind the tip, see [StrokeShaper]) is emitted once into a
/// cached [Path] of frozen pieces; each frame only the tail after it is
/// rebuilt. The result covers exactly what
/// `StrokeOutline.build(points, spec, complete: false)` covers.
class LiveStrokeBuilder {
  LiveStrokeBuilder(this.spec) : _shaper = StrokeShaper(spec.params) {
    _emitter = RibbonEmitter(
      _shaper,
      flatCaps: spec.flatCaps,
      width: spec.width,
      step: _shaper.p.step,
    );
  }

  final OutlineSpec spec;
  final StrokeShaper _shaper;
  late final RibbonEmitter _emitter;

  int _fed = 0;
  StrokePoint? _first;
  final Path _frozen = Path();
  RibbonCursor _cursor = (at: 0, cut: false);

  /// Sub-paths in the frozen part (pieces of about 24 world units).
  int frozenPieces = 0;

  /// Whether [points] extends the points of the previous [update].
  bool continues(List<StrokePoint> points) =>
      points.length >= _fed && (_fed == 0 || points.first == _first);

  /// The outline of [points], which must extend the previous call's
  /// points ([continues]).
  Path update(List<StrokePoint> points) {
    assert(continues(points));
    if (points.isEmpty) return Path();
    _first ??= points.first;
    StrokeOutline.feed(_shaper, points, spec, null, from: _fed);
    _fed = points.length;
    _shaper.update();
    if (!_shaper.started) return StrokeOutline.build(points, spec, complete: false);
    final out = Path();
    if (StrokeOutline.isDot(_shaper)) {
      StrokeOutline.dot(PathSink(out), _shaper, spec);
      return out;
    }
    final sink = _CountingSink(PathSink(_frozen));
    _cursor = _emitter.freeze(sink, _cursor, _shaper.finalCount);
    frozenPieces += sink.moves;
    out.addPath(_frozen, Offset.zero);
    _emitter.emit(PathSink(out), from: _cursor);
    return out;
  }

  /// The live outline of [points] drawn with [tool], [width] and [style]:
  /// built by [previous] when it is drawing the same stroke, else by a new
  /// builder (returned in `builder`; null for nib pens, which are rebuilt
  /// from scratch every frame).
  static ({Path path, LiveStrokeBuilder? builder}) build(
    LiveStrokeBuilder? previous,
    List<StrokePoint> points, {
    required InkTool tool,
    required double width,
    required StrokeStyle style,
  }) {
    if (PenProfile.of(tool).nibVariation > 0) {
      final path = StrokeRenderer.buildPath(
        points,
        tool: tool,
        width: width,
        style: style,
        complete: false,
      );
      return (path: path, builder: null);
    }
    final spec = StrokeRenderer.specFor(tool, width, style);
    final same = previous != null && previous.continues(points) && previous.spec.sameShape(spec);
    final builder = same ? previous : LiveStrokeBuilder(spec);
    return (path: builder.update(points), builder: builder);
  }
}

class _CountingSink implements OutlineSink {
  _CountingSink(this.inner);
  final OutlineSink inner;
  int moves = 0;

  @override
  void moveTo(double x, double y) {
    moves++;
    inner.moveTo(x, y);
  }

  @override
  void lineTo(double x, double y) => inner.lineTo(x, y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      inner.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void arc(double cx, double cy, double radius, double start, double sweep) =>
      inner.arc(cx, cy, radius, start, sweep);

  @override
  void close() => inner.close();
}

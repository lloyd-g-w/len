import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import '../input/live_ink.dart';
import 'outline_sink.dart';
import 'ribbon_emitter.dart';
import 'stroke_outline.dart';
import 'stroke_renderer.dart';
import 'stroke_shaper.dart';

/// The outline of a live stroke: its frozen part (unchanged since the
/// previous frame, except for appended pieces) and its tail. The tail starts
/// with a round cap inside the frozen part, so the two can be drawn one
/// after the other without a seam.
class LiveOutline {
  LiveOutline(this.frozen, this.tail);

  /// An outline that is all tail.
  LiveOutline.of(Path path) : frozen = null, tail = path;

  final Path? frozen;
  final Path tail;

  /// Both in one path (a copy of the frozen part: for translucent ink,
  /// which must be filled in one go, and for tests).
  Path get combined {
    final f = frozen;
    if (f == null) return tail;
    return Path()
      ..addPath(f, Offset.zero)
      ..addPath(tail, Offset.zero);
  }
}

/// Builds the outline of the stroke being drawn, frame by frame, in
/// constant time per frame, and its committed outline at pen-up.
///
/// The part of the outline that can no longer change (everything a few
/// pen-widths behind the tip, see [StrokeShaper]) is emitted once, as
/// frozen pieces (about 24 screen px each); each frame only the tail after
/// them is rebuilt. The result covers exactly what
/// `StrokeOutline.build(points, spec, complete: false)` covers.
///
/// At pen-up [finish] redoes only the end (the pen-up hook, the settled
/// last pressures): it rolls back to a recent checkpoint and completes
/// from there, so committing a long stroke costs no more than a frame.
class LiveStrokeBuilder {
  LiveStrokeBuilder(this.spec);

  final OutlineSpec spec;

  // Created once the stroke's unit is known: at once when the stroke
  // records it (`StrokeStyle.unit`), else after [StrokeOutline.unitPoints].
  StrokeShaper? _shaperOrNull;
  late StrokeShaper _shaper;
  late RibbonEmitter _emitter;

  final List<StrokePoint> _fed = [];

  /// The frozen pieces, and all of them in one path.
  final List<Path> _pieces = [];
  Path _frozen = Path();
  RibbonCursor _cursor = (at: 0, cut: false);

  /// Emitter state at each shaper checkpoint: (checkpoint id, cursor, pieces).
  final List<(int, RibbonCursor, int)> _checkpoints = [];

  /// Told why [finish] had to rebuild from scratch (tests).
  static void Function(String why)? debugFallback;

  /// Whether [points] extends the points of the previous [update].
  bool continues(List<StrokePoint> points) =>
      points.length >= _fed.length && (_fed.isEmpty || points.first == _fed.first);

  /// The outline of [points], which must extend the previous call's
  /// points ([continues]).
  LiveOutline update(List<StrokePoint> points) {
    assert(continues(points));
    if (points.isEmpty) return LiveOutline.of(Path());
    if (!_ready(points)) {
      return LiveOutline.of(StrokeOutline.build(points, spec, complete: false));
    }
    _feed(points);
    _shaper.update();
    if (!_shaper.started || _shaper.liveLength == 1) {
      // The start (pen-down hook) is undecided: the provisional line (with
      // the stabiliser on, or before anything is final: its first sample).
      final out = Path();
      StrokeOutline.emitLine(PathSink(out), _shaper, spec, live: true);
      return LiveOutline.of(out);
    }
    if (StrokeOutline.isDot(_shaper)) {
      final out = Path();
      StrokeOutline.dot(PathSink(out), _shaper, spec);
      return LiveOutline.of(out);
    }
    final shown = _shaper.liveLength;
    final piece = Path();
    _cursor = _emitter.freeze(PathSink(piece), _cursor, _shaper.finalCount, shown: shown);
    if (piece.getBounds() != Rect.zero) {
      _pieces.add(piece);
      _frozen.addPath(piece, Offset.zero);
    }
    _checkpoints.add((_shaper.checkpoint(), _cursor, _pieces.length));
    if (_checkpoints.length > 48) _checkpoints.removeAt(0);
    final tail = Path();
    // A cap rather than a cut where the tail meets the frozen part: drawn
    // separately, two paths sharing an edge would leave a hairline seam.
    // With the stabiliser on, only the final line ([StrokeShaper.liveLength],
    // which reaches past the frozen part).
    final emitter = shown < _shaper.length
        ? RibbonEmitter(
            RibbonPrefix(_shaper, shown),
            flatCaps: spec.flatCaps,
            width: spec.width,
            step: _shaper.p.step,
          )
        : _emitter;
    emitter.emit(PathSink(tail), from: (at: _cursor.at, cut: false));
    return LiveOutline(_frozen, tail);
  }

  /// The committed outline of the finished stroke [points] (the live
  /// points, possibly with a few more and the last pressures settled):
  /// what `StrokeOutline.build(points, spec)` builds, reusing the frozen
  /// part. [taperEnd] is the end taper of the committed stroke (world
  /// units; by default the spec's), which may follow the pen's speed at
  /// the lift; the pieces it reaches are emitted again.
  Path finish(List<StrokePoint> points, {double? taperEnd}) {
    final spec = this.spec.withTaperEnd(taperEnd ?? this.spec.taperEnd);
    if (_shaperOrNull == null || !_shaper.started || points.isEmpty) {
      return StrokeOutline.build(points, spec);
    }
    // The first point that differs from what was fed (the settled end).
    var changed = math.min(_fed.length, points.length);
    for (var i = math.max(0, _fed.length - 8); i < changed; i++) {
      if (points[i] != _fed[i]) {
        changed = i;
        break;
      }
    }
    var sample = _shaper.sampleOfPoint(math.max(0, changed - 1));
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = _shaper.rollBack(sample);
      final at = id == null ? -1 : _checkpoints.indexWhere((c) => c.$1 == id);
      if (at < 0) {
        debugFallback?.call(
          'no checkpoint for sample $sample (id $id, ${_checkpoints.length} kept)',
        );
        return StrokeOutline.build(points, spec);
      }
      final (_, cursor, pieces) = _checkpoints[at];
      _checkpoints.removeRange(at + 1, _checkpoints.length);
      _cursor = cursor;
      _setPieces(pieces);
      _fed.removeRange(_shaper.pointCount, _fed.length);
      _feed(points);
      // The pen-up hook may reach back further than the change.
      final keep = _shaper.endKeep();
      if (keep - 1 >= sample || attempt == 1) {
        if (keep - 1 < sample) {
          debugFallback?.call('keep $keep < sample $sample');
          return StrokeOutline.build(points, spec);
        }
        _shaper
          ..taperEnd = spec.taperEnd
          ..update(ended: true, keep: keep);
        final out = Path();
        if (StrokeOutline.isDot(_shaper)) {
          StrokeOutline.dot(PathSink(out), _shaper, spec);
          return out;
        }
        // The end taper's pieces, and a flat end's (cut off at the end).
        final redo = math.min(_shaper.taperedFrom, _emitter.endZoneFrom());
        if (!_unfreeze(redo)) return StrokeOutline.build(points, spec);
        out.addPath(_frozen, Offset.zero);
        _emitter.emit(PathSink(out), from: _cursor);
        return out;
      }
      sample = keep - 1;
    }
    return StrokeOutline.build(points, spec);
  }

  /// Drops the frozen pieces that depend on samples from [sample] on (the
  /// end taper's, a flat end's), back to the latest checkpoint before them; false when
  /// there is none.
  bool _unfreeze(int sample) {
    // A piece up to sample q depends on samples up to q + 2 (the tangent
    // and fold tests look one and two ahead).
    if (_cursor.at + 3 <= sample) return true;
    var k = _checkpoints.length - 1;
    while (k >= 0 && _checkpoints[k].$2.at + 3 > sample) {
      k--;
    }
    if (k < 0) {
      if (sample >= 3) {
        debugFallback?.call('no checkpoint before the end at $sample');
        return false;
      }
      _cursor = (at: 0, cut: false);
      _setPieces(0);
      return true;
    }
    final (_, cursor, pieces) = _checkpoints[k];
    _cursor = cursor;
    _setPieces(pieces);
    return true;
  }

  void _setPieces(int count) {
    if (count >= _pieces.length) return;
    _pieces.removeRange(count, _pieces.length);
    _frozen = Path();
    for (final p in _pieces) {
      _frozen.addPath(p, Offset.zero);
    }
  }

  bool _ready(List<StrokePoint> points) {
    if (_shaperOrNull != null) return true;
    // Too few points to tell the stroke's unit: build from scratch.
    if (spec.unit <= 0 && points.length < StrokeOutline.unitPoints) return false;
    _shaper = _shaperOrNull = StrokeShaper(StrokeOutline.paramsOf(points, spec));
    _emitter = RibbonEmitter(
      _shaper,
      flatCaps: spec.flatCaps,
      width: spec.width,
      step: _shaper.p.step,
    );
    return true;
  }

  void _feed(List<StrokePoint> points) {
    final from = _fed.length;
    StrokeOutline.feed(_shaper, points, spec, from: from);
    _fed.addAll(points.skip(from));
  }

  // ---------------------------------------------------------------------------
  // The live stroke of a [LiveInk]

  static final Expando<LiveStrokeBuilder> _builders = Expando('live stroke builders');

  /// The [LiveInk.generation] each live stroke's builder was started in.
  static final Expando<int> _generations = Expando('live stroke generations');

  /// The builder of [live]'s stroke, unless its points were replaced since.
  static LiveStrokeBuilder? _builderOf(LiveInk live) =>
      _generations[live] == live.generation ? _builders[live] : null;

  /// The live outline of [live]'s stroke, built incrementally.
  static LiveOutline livePath(LiveInk live) {
    final previous = _builderOf(live);
    _generations[live] = live.generation;
    final built = build(previous, live.points, width: live.width, style: live.style);
    _builders[live] = built.builder;
    return built.path;
  }

  /// The committed outline of [points], the finished stroke of [live]
  /// (drawn with [tool], [width] and [style]), from the builder that drew it
  /// live; null when there is none.
  static Path? finishLive(
    LiveInk live,
    List<StrokePoint> points, {
    required double width,
    required StrokeStyle style,
  }) {
    final builder = _builderOf(live);
    _builders[live] = null;
    if (builder == null || points.isEmpty || points.first != builder._fed.firstOrNull) return null;
    final spec = StrokeRenderer.specFor(width, style);
    if (!builder.spec.sameLiveShape(spec)) return null;
    return builder.finish(points, taperEnd: spec.taperEnd);
  }

  /// The live outline of [points] drawn with [tool], [width] and [style]:
  /// built by [previous] when it is drawing the same stroke, else by a new
  /// builder (returned in `builder`).
  static ({LiveOutline path, LiveStrokeBuilder builder}) build(
    LiveStrokeBuilder? previous,
    List<StrokePoint> points, {
    required double width,
    required StrokeStyle style,
  }) {
    final spec = StrokeRenderer.specFor(width, style);
    final same = previous != null && previous.continues(points) && previous.spec.sameShape(spec);
    final builder = same ? previous : LiveStrokeBuilder(spec);
    return (path: builder.update(points), builder: builder);
  }
}

import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../domain/stroke.dart';
import 'growable.dart';
import 'outline_sink.dart';
import 'stroke_renderer.dart';

/// Builds the outlines of strokes loaded from storage before they are
/// drawn. Outlines take a few hundred microseconds per stroke, so a page
/// with thousands of strokes would otherwise stall the frame that first
/// draws it for a second; implementations compute them elsewhere (a worker
/// isolate, `platform/outline_preparer`) and memoise them with
/// [StrokeRenderer.adopt].
abstract class OutlinePreparer {
  /// Completes once every stroke in [strokes] has its outline memoised.
  ///
  /// [onReady], if given, is told about the strokes as their outlines are
  /// memoised, a slice at a time and roughly in the order given (so a
  /// caller can show the first ones while the rest are still being
  /// built); every stroke is reported exactly once, before the future
  /// completes.
  Future<void> prepare(List<Stroke> strokes, {void Function(List<Stroke> ready)? onReady});

  /// Stops any workers.
  void close() {}
}

/// Builds outlines right away on the calling thread (tests; the fallback).
/// The returned future is synchronous, so callers continue at once.
class InlineOutlinePreparer implements OutlinePreparer {
  const InlineOutlinePreparer();

  @override
  Future<void> prepare(List<Stroke> strokes, {void Function(List<Stroke> ready)? onReady}) {
    for (final stroke in strokes) {
      StrokeRenderer.pathOf(stroke);
    }
    if (strokes.isNotEmpty) onReady?.call(strokes);
    return SynchronousFuture(null);
  }

  @override
  void close() {}
}

/// Outline segments as numbers, so they can be computed in another isolate
/// and turned into a [Path] on the UI thread ([OutlineCommands.toPath]).
class OutlineCommands implements OutlineSink {
  final DoubleBuffer _data = DoubleBuffer(256);

  static const double _move = 0, _line = 1, _cubic = 2, _arc = 3, _close = 4;

  /// The outline of [stroke], recorded.
  static Float64List of(Stroke stroke) => (OutlineCommands()..add(stroke))._data.toList();

  /// The outlines of [strokes], recorded one after another into one list,
  /// and where each one ends in it.
  static (Float64List, Int32List) ofAll(List<Stroke> strokes) {
    final commands = OutlineCommands();
    final ends = Int32List(strokes.length);
    for (var i = 0; i < strokes.length; i++) {
      commands.add(strokes[i]);
      ends[i] = commands._data.length;
    }
    return (commands._data.toList(), ends);
  }

  /// Appends the outline of [stroke].
  void add(Stroke stroke) => StrokeRenderer.emitOutline(
    this,
    stroke.points,
    tool: stroke.tool,
    width: stroke.width,
    style: stroke.style,
    complete: true,
  );

  @override
  void moveTo(double x, double y) => _data
    ..add(_move)
    ..add(x)
    ..add(y);

  @override
  void lineTo(double x, double y) => _data
    ..add(_line)
    ..add(x)
    ..add(y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) => _data
    ..add(_cubic)
    ..add(x1)
    ..add(y1)
    ..add(x2)
    ..add(y2)
    ..add(x3)
    ..add(y3);

  @override
  void arc(double cx, double cy, double radius, double start, double sweep) => _data
    ..add(_arc)
    ..add(cx)
    ..add(cy)
    ..add(radius)
    ..add(start)
    ..add(sweep);

  @override
  void close() => _data.add(_close);

  /// Builds the path recorded in [data].
  static Path toPath(Float64List data) {
    final path = Path();
    var i = 0;
    while (i < data.length) {
      final op = data[i];
      if (op == _move) {
        path.moveTo(data[i + 1], data[i + 2]);
        i += 3;
      } else if (op == _line) {
        path.lineTo(data[i + 1], data[i + 2]);
        i += 3;
      } else if (op == _cubic) {
        path.cubicTo(data[i + 1], data[i + 2], data[i + 3], data[i + 4], data[i + 5], data[i + 6]);
        i += 7;
      } else if (op == _arc) {
        final rect = Rect.fromCircle(center: Offset(data[i + 1], data[i + 2]), radius: data[i + 3]);
        path.arcTo(rect, data[i + 4], data[i + 5], false);
        i += 6;
      } else {
        path.close();
        i += 1;
      }
    }
    return path;
  }
}

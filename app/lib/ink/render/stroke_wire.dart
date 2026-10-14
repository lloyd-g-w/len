import 'dart:typed_data';

import '../../domain/stroke.dart';

/// Strokes packed into a [Float64List] for an outline worker: the tool,
/// the width, the style and the points, which is all an outline needs.
abstract final class StrokeWire {
  /// Per stroke: tool, width, the style's nine numbers, the point count,
  /// then x, y, pressure of each point.
  static const int header = 12;

  /// [strokes] as one list of numbers (only what their outlines need).
  static Float64List pack(List<Stroke> strokes) {
    var length = 0;
    for (final s in strokes) {
      length += header + 3 * s.points.length;
    }
    final data = Float64List(length);
    var i = 0;
    for (final s in strokes) {
      final style = s.style;
      data
        ..[i++] = s.tool.index.toDouble()
        ..[i++] = s.width
        ..[i++] = style.opacity
        ..[i++] = style.thinning
        ..[i++] = style.streamline
        ..[i++] = style.unit
        ..[i++] = style.ends.index.toDouble()
        ..[i++] = style.taperStart
        ..[i++] = style.taperEnd
        ..[i++] = style.startPhase
        ..[i++] = style.cutEnd ? 1 : 0
        ..[i++] = s.points.length.toDouble();
      for (final p in s.points) {
        data
          ..[i++] = p.x
          ..[i++] = p.y
          ..[i++] = p.pressure;
      }
    }
    return data;
  }

  /// The strokes [pack] packed into [data] (no ids, colours or times).
  static List<Stroke> unpack(Float64List data) {
    final strokes = <Stroke>[];
    var i = 0;
    while (i < data.length) {
      final tool = InkTool.values[data[i].toInt()];
      final width = data[i + 1];
      final style = StrokeStyle(
        opacity: data[i + 2],
        thinning: data[i + 3],
        streamline: data[i + 4],
        unit: data[i + 5],
        ends: StrokeEnds.values[data[i + 6].toInt()],
        taperStart: data[i + 7],
        taperEnd: data[i + 8],
        startPhase: data[i + 9],
        cutEnd: data[i + 10] != 0,
      );
      final n = data[i + 11].toInt();
      i += header;
      strokes.add(
        Stroke(
          id: '',
          surfaceId: '',
          tool: tool,
          color: 0,
          width: width,
          style: style,
          createdAt: 0,
          points: [
            for (var k = 0; k < n; k++)
              StrokePoint(data[i + 3 * k], data[i + 3 * k + 1], data[i + 3 * k + 2]),
          ],
        ),
      );
      i += 3 * n;
    }
    return strokes;
  }
}

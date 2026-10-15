import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../domain/text/text_data.dart';
import '../../../ink/elements/text_box_layout.dart';

/// A rectangle to highlight, rotated about its own centre.
typedef RotatedRect = ({Rect rect, double rotation});

/// Where search matches lie in a text box: one rectangle per line each
/// [ranges] entry covers, where the box's own layout puts the text, in
/// page coordinates (rotated with the box).
///
/// [body] is the indexed text (the box's text trimmed); [json] the stored
/// data. Null when the box's text doesn't contain [body] (changed since).
List<List<RotatedRect>>? textMatchRects({
  required String json,
  required Rect box,
  required double rotation,
  required String body,
  required List<({int start, int end})> ranges,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final data = TextData.fromJson(decoded);
  final lead = data.text.indexOf(body);
  if (lead < 0) return null;
  // (Auto-width boxes are as wide as their text: nothing wraps.)
  final layout = TextBoxLayout(data, box.width);
  final centre = box.center;
  final cos = math.cos(rotation), sin = math.sin(rotation);
  RotatedRect place(Rect local) {
    final r = local.shift(box.topLeft);
    final d = r.center - centre;
    final c = centre + Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos);
    return (rect: Rect.fromCenter(center: c, width: r.width, height: r.height), rotation: rotation);
  }

  try {
    return [
      for (final range in ranges)
        [for (final b in layout.boxesOf(lead + range.start, lead + range.end)) place(b.toRect())],
    ];
  } finally {
    layout.dispose();
  }
}

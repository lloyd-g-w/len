import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../elements/text_layout.dart';
import 'handwriting_recognizer.dart';
import 'ink_clustering.dart';

/// What recognising a lasso selection found: the text (one line of text
/// per line of handwriting) and, for a single line, the alternatives.
class ConversionResult {
  const ConversionResult({required this.text, required this.alternatives});

  /// The best reading (lines joined with `\n`).
  final String text;

  /// Other readings, best first (single lines only; empty otherwise).
  final List<String> alternatives;

  bool get isEmpty => text.trim().isEmpty;
}

/// "Convert to text": recognises selected strokes line by line and makes
/// the text box that replaces them.
abstract final class ConvertToText {
  /// Font size relative to the handwriting's letter height (a stroke's
  /// height spans about a capital letter).
  static const double fontPerLetterHeight = 1.25;

  /// Recognises [strokes] with [recognize], line by line (as clustered for
  /// search), top to bottom.
  static Future<ConversionResult> recognize(
    List<Stroke> strokes,
    Future<List<RecognitionCandidate>> Function(List<Stroke> line, Size writingArea) recognize,
  ) async {
    final lines = InkClustering.lines(strokes);
    final texts = <String>[];
    var alternatives = const <String>[];
    for (final line in lines) {
      final area = Size(line.bounds.width + line.letterHeight, line.letterHeight * 2.5);
      final candidates = await recognize(line.strokes, area);
      final readings = [
        for (final c in candidates)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ];
      if (readings.isEmpty) continue;
      texts.add(readings.first);
      if (lines.length == 1) alternatives = readings.skip(1).toSet().take(5).toList();
    }
    return ConversionResult(text: texts.join('\n'), alternatives: alternatives);
  }

  /// A text box showing [text] where [strokes] were: at their top left,
  /// in their (most common) colour, its font sized like the handwriting,
  /// as wide as the ink (wrapping; wider only for a long word).
  ///
  /// [area] (surface coordinates; the visible part of the page or canvas)
  /// keeps the box inside: it wraps narrower or moves left to fit.
  static SurfaceElement textBox(
    List<Stroke> strokes,
    String text, {
    required String id,
    required String surfaceId,
    required double z,
    required int createdAt,
    Rect? area,
  }) {
    final ink = [
      for (final s in strokes)
        if (!s.tool.isHighlighter) s,
    ];
    final source = ink.isEmpty ? strokes : ink;
    var bounds = InkClustering.inkBounds(source.first);
    for (final s in source.skip(1)) {
      bounds = bounds.expandToInclude(InkClustering.inkBounds(s));
    }
    final lines = InkClustering.lines(source);
    final letter = lines.isEmpty
        ? bounds.height
        : (lines.map((l) => l.letterHeight).toList()..sort())[lines.length ~/ 2];
    final data = TextData(
      text: text,
      fontSize: (letter * fontPerLetterHeight)
          .clamp(TextData.minFontSize, math.min(TextData.maxFontSize, 160))
          .toDouble(),
      color: _commonColour(source),
    );
    // The ink's width, but no narrower than the longest word.
    var width = math.max(bounds.width, _longestWord(data));
    var left = bounds.left;
    if (area != null) {
      final inside = area.deflate(math.min(_margin, area.shortestSide / 8));
      width = math.min(width, math.max(inside.width, TextLayout.minWidth));
      if (left + width > inside.right) left = math.max(inside.left, inside.right - width);
    }
    final height = TextLayout.heightOf(data, width);
    return SurfaceElement(
      id: id,
      surfaceId: surfaceId,
      type: ElementType.text.name,
      rect: Rect.fromLTWH(left, bounds.top, width, height),
      z: z,
      createdAt: createdAt,
      data: data.toJson(),
    );
  }

  /// Room kept between a converted box and the edge of its area.
  static const double _margin = 12;

  /// The width of [data]'s longest word (it can't wrap narrower).
  static double _longestWord(TextData data) {
    final layout = TextBoxLayout(data, double.infinity);
    final width = layout.painter.minIntrinsicWidth;
    layout.dispose();
    return (width + TextLayout.autoWidthSlack).ceilToDouble();
  }

  static int _commonColour(List<Stroke> strokes) {
    final counts = <int, int>{};
    for (final s in strokes) {
      counts[s.color] = (counts[s.color] ?? 0) + s.points.length;
    }
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

import 'package:flutter/painting.dart';

import '../../domain/text_data.dart';

/// Lays out text-box content. The renderer and the on-canvas text editor
/// use the same [styleOf] / [alignOf], so text wraps identically while it
/// is edited and once committed.
abstract final class TextLayout {
  /// Minimum width of a text box, in world units.
  static const double minWidth = 24;

  /// A complete style ([TextStyle.inherit] off), so the text field used
  /// for editing cannot pick up theme properties (e.g. letter spacing)
  /// that the renderer would not apply.
  static TextStyle styleOf(TextData data) => TextStyle(
    inherit: false,
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['Segoe UI', 'Cantarell', 'Ubuntu', 'DejaVu Sans', 'Arial'],
    fontSize: data.fontSize,
    height: 1.25,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: 0,
    wordSpacing: 0,
    textBaseline: TextBaseline.alphabetic,
    color: Color(data.color),
    fontWeight: data.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: data.italic ? FontStyle.italic : FontStyle.normal,
  );

  static TextAlign alignOf(TextData data) => switch (data.align) {
    TextAlignment.left => TextAlign.left,
    TextAlignment.center => TextAlign.center,
    TextAlignment.right => TextAlign.right,
  };

  /// A laid-out painter for [data] wrapped at [width]. The caller disposes it.
  static TextPainter layout(TextData data, double width) {
    final painter = TextPainter(
      text: TextSpan(
        // An empty box still has one line's height.
        text: data.text.isEmpty ? ' ' : data.text,
        style: styleOf(data),
      ),
      textAlign: alignOf(data),
      textDirection: TextDirection.ltr,
    );
    final w = width < minWidth ? minWidth : width;
    return painter..layout(minWidth: w, maxWidth: w);
  }

  /// Height of [data] wrapped at [width].
  static double heightOf(TextData data, double width) {
    final painter = layout(data, width);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

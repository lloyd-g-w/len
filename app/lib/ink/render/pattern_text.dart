import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../domain/paper_pattern.dart';

/// Lays out and paints [PatternLabel]s, caching the laid-out paragraphs
/// (planner pages repaint the same few dozen labels every frame).
abstract final class PatternText {
  static final Map<(String, double, double, bool, LabelAlign, Color), ui.Paragraph> _cache = {};
  static const int _capacity = 600;

  static void paint(Canvas canvas, PatternLabel label, Color color) {
    final key = (label.text, label.size, label.box.width, label.bold, label.align, color);
    var paragraph = _cache.remove(key);
    if (paragraph == null) {
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: switch (label.align) {
                  LabelAlign.start => TextAlign.left,
                  LabelAlign.center => TextAlign.center,
                  LabelAlign.end => TextAlign.right,
                },
                maxLines: 1,
                ellipsis: '…',
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: color,
                // The UI font (falls back to the platform's where missing).
                fontFamily: 'Roboto',
                fontSize: label.size,
                fontWeight: label.bold ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: label.bold && label.size < 12 ? label.size * 0.06 : 0,
              ),
            )
            ..addText(label.text);
      paragraph = builder.build()..layout(ui.ParagraphConstraints(width: label.box.width));
      if (_cache.length >= _capacity) _cache.remove(_cache.keys.first)?.dispose();
    }
    _cache[key] = paragraph; // Most recently used last.
    canvas.drawParagraph(
      paragraph,
      Offset(label.box.left, label.box.center.dy - paragraph.height / 2),
    );
  }
}

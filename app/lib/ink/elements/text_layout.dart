import 'package:flutter/widgets.dart';

import '../../domain/text/rich_text_buffer.dart';
import '../../domain/text/text_data.dart';
import 'list_marker.dart';

/// Builds and lays out text-box content. The renderer, the PDF export and
/// the on-canvas text editor all use the same [spanOf] / [styleFor] /
/// [alignOf], so text wraps identically while it is edited and once
/// committed — and, since text boxes only use the bundled fonts, on every
/// device.
///
/// List markers are inline placeholders at the start of their line (one
/// U+FFFC in the laid-out text, see [MarkerOffsets]).
abstract final class TextLayout {
  /// Minimum width of a text box, in world units.
  static const double minWidth = 24;

  /// Line height, as a multiple of the font size.
  static const double lineHeight = 1.25;

  /// Extra width given to auto-width boxes beyond their text, so rounding
  /// never wraps their last word.
  static const double autoWidthSlack = 2;

  /// For characters the bundled fonts lack (e.g. CJK, emoji).
  static const List<String> fallback = [
    'Noto Sans',
    'Segoe UI',
    'Cantarell',
    'Ubuntu',
    'DejaVu Sans',
    'Arial',
  ];

  /// Font size of text in paragraph [para] formatted as [span].
  static double sizeOf(TextData box, SpanStyle span, ParaStyle para) =>
      span.size ?? box.fontSize * para.sizeFactor;

  /// A complete style ([TextStyle.inherit] off), so the text field used
  /// for editing cannot pick up theme properties (e.g. letter spacing)
  /// that the renderer would not apply.
  static TextStyle styleFor(TextData box, SpanStyle span, ParaStyle para) {
    final checked = para.list == ListKind.check && para.checked;
    var color = Color(span.color ?? box.color);
    if (checked) color = color.withValues(alpha: color.a * 0.5);
    final highlight = span.highlight;
    return TextStyle(
      inherit: false,
      fontFamily: (span.font ?? box.font).family,
      fontFamilyFallback: fallback,
      fontSize: sizeOf(box, span, para),
      height: lineHeight,
      leadingDistribution: TextLeadingDistribution.even,
      letterSpacing: 0,
      wordSpacing: 0,
      textBaseline: TextBaseline.alphabetic,
      color: color,
      fontWeight: span.bold || para.heading > 0 ? FontWeight.w700 : FontWeight.w400,
      fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
      decoration: TextDecoration.combine([
        if (span.underline) TextDecoration.underline,
        if (span.strike || checked) TextDecoration.lineThrough,
      ]),
      decorationColor: color,
      background: highlight == null ? null : (Paint()..color = Color(highlight)),
    );
  }

  /// The style of unformatted body text of [box].
  static TextStyle baseStyle(TextData box) => styleFor(box, SpanStyle.plain, ParaStyle.body);

  static TextAlign alignOf(TextData data) => switch (data.align) {
    TextAlignment.left => TextAlign.left,
    TextAlignment.center => TextAlign.center,
    TextAlignment.right => TextAlign.right,
  };

  /// The list markers of [data], in line order.
  static List<ListMarker> markersOf(TextData data) {
    final paras = data.paras;
    final chars = data.charStyles();
    final markers = <ListMarker>[];
    var start = 0;
    for (var line = 0; line < paras.length; line++) {
      final para = paras[line];
      if (para.isList) {
        final first = start < data.text.length && data.text.codeUnitAt(start) != 0x0A
            ? chars[start]
            : SpanStyle.plain;
        markers.add(
          ListMarker(
            line: line,
            para: para,
            number: RichTextBuffer.listNumberOf(paras, line),
            fontSize: sizeOf(data, first, para),
            color: first.color ?? data.color,
            font: first.font ?? data.font,
          ),
        );
      }
      final end = data.text.indexOf('\n', start);
      start = end < 0 ? data.text.length : end + 1;
    }
    return markers;
  }

  /// The styled content of [data]: per line its marker (built by
  /// [marker]) and its runs. [underlined] (model offsets) is underlined,
  /// e.g. the IME composing range.
  static TextSpan spanOf(
    TextData data, {
    required InlineSpan Function(ListMarker marker) marker,
    TextRange underlined = TextRange.empty,
  }) {
    final text = data.text;
    final chars = data.charStyles();
    final paras = data.paras;
    final markers = {for (final m in markersOf(data)) m.line: m};
    bool under(int i) => underlined.isValid && i >= underlined.start && i < underlined.end;
    final children = <InlineSpan>[];
    var start = 0;
    for (var line = 0; line < paras.length; line++) {
      final para = paras[line];
      if (markers[line] case final m?) children.add(marker(m));
      final nl = text.indexOf('\n', start);
      final end = nl < 0 ? text.length : nl;
      var i = start;
      while (i < end) {
        var j = i + 1;
        while (j < end && chars[j] == chars[i] && under(j) == under(i)) {
          j++;
        }
        var style = styleFor(data, chars[i], para);
        if (under(i)) {
          style = style.copyWith(
            decoration: TextDecoration.combine([?style.decoration, TextDecoration.underline]),
          );
        }
        children.add(TextSpan(text: text.substring(i, j), style: style));
        i = j;
      }
      if (nl >= 0) {
        // The break takes the line's last style, so an empty line is as
        // tall as its paragraph.
        final last = end > start ? chars[end - 1] : SpanStyle.plain;
        children.add(TextSpan(text: '\n', style: styleFor(data, last, para)));
      }
      start = nl < 0 ? text.length : nl + 1;
    }
    return TextSpan(style: baseStyle(data), children: children);
  }

  /// A laid-out [TextBoxLayout] of [data] wrapped at [width]. The caller
  /// disposes it.
  static TextBoxLayout layout(TextData data, double width) => TextBoxLayout(data, width);

  /// Height of [data] wrapped at [width].
  static double heightOf(TextData data, double width) {
    final layout = TextBoxLayout(data, width);
    final height = layout.height;
    layout.dispose();
    return height;
  }

  /// The width [data] needs without wrapping (auto-width boxes).
  static double naturalWidth(TextData data) {
    final layout = TextBoxLayout(data, double.infinity);
    final width = layout.painter.maxIntrinsicWidth;
    layout.dispose();
    final w = (width + autoWidthSlack).ceilToDouble();
    return w < minWidth ? minWidth : w;
  }
}

/// [TextLayout] of one text box: a laid-out painter plus its list markers.
class TextBoxLayout {
  TextBoxLayout(this.data, double width) : markers = TextLayout.markersOf(data) {
    final span = TextLayout.spanOf(
      data,
      // Only the placeholder's size matters here; markers are painted
      // separately.
      marker: (m) =>
          const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox.shrink()),
    );
    painter = TextPainter(
      // An empty box still has one line's height.
      text: span.children!.isEmpty ? TextSpan(text: ' ', style: span.style) : span,
      textAlign: TextLayout.alignOf(data),
      textDirection: TextDirection.ltr,
    );
    painter.setPlaceholderDimensions([
      for (final m in markers)
        PlaceholderDimensions(size: m.size, alignment: PlaceholderAlignment.middle),
    ]);
    if (width.isFinite) {
      final w = width < TextLayout.minWidth ? TextLayout.minWidth : width;
      painter.layout(minWidth: w, maxWidth: w);
    } else {
      painter.layout();
    }
  }

  final TextData data;
  late final TextPainter painter;
  final List<ListMarker> markers;

  double get height => painter.height;

  /// The placeholder box of each of [markers] (local coordinates).
  List<Rect> get markerBoxes => [
    for (final b in painter.inlinePlaceholderBoxes ?? const <TextBox>[]) b.toRect(),
  ];

  /// Paints the text with its top left at [origin].
  void paint(Canvas canvas, Offset origin) {
    painter.paint(canvas, origin);
    final boxes = markerBoxes;
    for (var i = 0; i < markers.length && i < boxes.length; i++) {
      markers[i].paint(
        canvas,
        boxes[i].shift(origin),
        number: (label, column) => paintNumber(canvas, markers[i], label, column),
      );
    }
  }

  /// The line of the checkbox at [local] (box coordinates), if any.
  int? checkboxAt(Offset local) {
    final boxes = markerBoxes;
    for (var i = 0; i < markers.length && i < boxes.length; i++) {
      final m = markers[i];
      if (m.para.list != ListKind.check) continue;
      if (m.checkbox(boxes[i]).inflate(m.fontSize * 0.3).contains(local)) return m.line;
    }
    return null;
  }

  /// Paints a numbered item's [label] right-aligned in [column].
  static void paintNumber(Canvas canvas, ListMarker marker, String label, Rect column) {
    final p = numberPainter(marker, label);
    p.paint(canvas, numberOrigin(marker, p, column));
    p.dispose();
  }

  /// Lays out a number label (the caller disposes it).
  static TextPainter numberPainter(ListMarker marker, String label) => TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        inherit: false,
        fontFamily: marker.font.family,
        fontFamilyFallback: TextLayout.fallback,
        fontSize: marker.fontSize,
        height: 1,
        color: Color(marker.color),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Top left of a number label: right-aligned, vertically centred.
  static Offset numberOrigin(ListMarker marker, TextPainter label, Rect column) => Offset(
    column.right - marker.fontSize * 0.35 - label.width,
    column.center.dy - label.height / 2,
  );

  void dispose() => painter.dispose();
}

/// Maps offsets between a text box's text (model offsets) and the laid-out
/// text, which has one placeholder character before each list line.
class MarkerOffsets {
  MarkerOffsets(TextData data) : _starts = _listStarts(data);

  /// Model offsets of the starts of list lines, ascending.
  final List<int> _starts;

  static List<int> _listStarts(TextData data) {
    final out = <int>[];
    var start = 0;
    for (final p in data.paras) {
      if (p.isList) out.add(start);
      final nl = data.text.indexOf('\n', start);
      if (nl < 0) break;
      start = nl + 1;
    }
    return out;
  }

  bool get isEmpty => _starts.isEmpty;

  /// Display offset of model offset [m]: after the marker of its line.
  int toDisplay(int m) {
    var n = 0;
    while (n < _starts.length && _starts[n] <= m) {
      n++;
    }
    return m + n;
  }

  /// Model offset of display offset [d] (a marker maps to its line start).
  int toModel(int d) {
    var n = 0;
    while (n < _starts.length && _starts[n] + n < d) {
      n++;
    }
    return d - n;
  }

  /// Whether display offset [d] is just before a marker.
  bool isBeforeMarker(int d) {
    for (var n = 0; n < _starts.length; n++) {
      if (_starts[n] + n == d) return true;
    }
    return false;
  }

  /// The laid-out text of [text].
  String display(String text) {
    if (_starts.isEmpty) return text;
    final out = StringBuffer();
    var last = 0;
    for (final s in _starts) {
      out
        ..write(text.substring(last, s))
        ..write('\uFFFC');
      last = s;
    }
    out.write(text.substring(last));
    return out.toString();
  }
}

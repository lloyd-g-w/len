import 'package:flutter/widgets.dart';

import '../../domain/text/rich_text_buffer.dart';
import '../../domain/text/text_data.dart';
import 'list_marker.dart';
import 'text_box_layout.dart';
import 'text_insert.dart';
import 'text_plan.dart';

export 'list_marker.dart';
export 'marker_offsets.dart';
export 'text_box_layout.dart';
export 'text_insert.dart';
export 'text_plan.dart';
export 'text_spacing.dart';
export 'text_wraps.dart';

/// Builds and lays out text-box content. The renderer, the PDF export and
/// the on-canvas text editor all use the same [TextPlan] and [spanOf] /
/// [styleFor] / [alignOf], so text wraps identically while it is edited
/// and once committed — and, since text boxes only use the bundled fonts,
/// on every device.
///
/// List markers are inline placeholders at the start of their line (one
/// U+FFFC in the laid-out text, see [MarkerOffsets]); wrapped list items
/// get hanging indents and paragraphs running against the box's direction
/// their own alignment ([TextPlan]).
abstract final class TextLayout {
  /// Minimum width of a text box, in world units.
  static const double minWidth = 24;

  /// Line height, as a multiple of the font size.
  static const double lineHeight = 1.25;

  /// Extra width given to auto-width boxes beyond their text, so rounding
  /// never wraps their last word.
  static const double autoWidthSlack = 2;

  /// For characters the text-box fonts lack: the bundled Arabic and
  /// Hebrew fonts, then system fonts (e.g. CJK, emoji).
  static final List<String> fallback = [
    for (final f in FallbackFont.values) f.family,
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

  /// The strut of a box: none to speak of (headings keep their height),
  /// but its fonts' metrics still settle lines mixing fonts (e.g. Arabic
  /// from the fallback font). The editing field's strut is the same
  /// (`EditableText` gives it the field's style).
  static StrutStyle strutOf(TextData box) =>
      StrutStyle.disabled.inheritFromTextStyle(baseStyle(box));

  /// The style of unformatted body text of [box].
  static TextStyle baseStyle(TextData box) => styleFor(box, SpanStyle.plain, ParaStyle.body);

  /// The paragraph alignment of [data] (relative to the box's direction,
  /// [TextPlan.base]).
  static TextAlign alignOf(TextData data) => switch (data.align) {
    TextAlignment.start => TextAlign.start,
    TextAlignment.center => TextAlign.center,
    TextAlignment.end => TextAlign.end,
  };

  /// The list markers of [data], in line order; [directions] are its
  /// paragraphs' ([TextData.directions]). A box continuing a list item
  /// from the page before ([TextFlow.joined]) starts with a
  /// [ListMarker.continued] one; numbers run on ([TextFlow.numbers]).
  static List<ListMarker> markersOf(TextData data, [List<TextDirection>? directions]) {
    final dirs = directions ?? data.directions;
    final flow = data.flow;
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
            number: RichTextBuffer.listNumberOf(paras, line, flow?.numbers ?? const []),
            fontSize: sizeOf(data, first, para),
            color: first.color ?? data.color,
            font: first.font ?? data.font,
            direction: dirs[line],
            continued: line == 0 && (flow?.joined ?? false),
          ),
        );
      }
      final end = data.text.indexOf('\n', start);
      start = end < 0 ? data.text.length : end + 1;
    }
    return markers;
  }

  /// The styled content of [data] laid out by [plan]: per line its runs
  /// and the plan's inserts: markers (built by [marker]), gaps and padding
  /// (built by [gap]), page-break rooms (by [room]), paragraph spacing (by
  /// [spacing]), breaks and isolates. [underlined] (model offsets) is
  /// underlined, e.g. the IME composing range.
  static TextSpan spanOf(
    TextData data,
    TextPlan plan, {
    required InlineSpan Function(ListMarker marker) marker,
    InlineSpan Function(Size size) gap = gapSpan,
    InlineSpan Function(double height) room = roomSpan,
    InlineSpan Function(double height) spacing = spacingSpan,
    TextRange underlined = TextRange.empty,
  }) {
    final text = data.text;
    final chars = data.charStyles();
    final paras = data.paras;
    final inserts = plan.inserts;
    final children = <InlineSpan>[];
    var next = 0;
    var start = 0;
    for (var line = 0; line < paras.length; line++) {
      final para = paras[line];
      final nl = text.indexOf('\n', start);
      final end = nl < 0 ? text.length : nl;
      var from = start;
      while (next < inserts.length && inserts[next].at <= end) {
        final insert = inserts[next++];
        lineRuns(data, chars, para, from, insert.at, children, underlined: underlined);
        from = insert.at;
        // Breaks and isolates take the style around them (so the line
        // keeps its height) without decorations or highlight.
        final around = styleFor(
          data,
          from > start ? chars[from - 1] : (from < end ? chars[from] : SpanStyle.plain),
          para,
        ).copyWith(decoration: TextDecoration.none, background: _clear);
        for (final piece in insert.pieces) {
          children.add(switch (piece.kind) {
            InsertKind.marker => marker(piece.marker!),
            InsertKind.space => gap(piece.size),
            InsertKind.room => room(piece.size.height),
            InsertKind.spacing => spacing(piece.size.height),
            InsertKind.roomBreak => const TextSpan(text: '\n', style: _roomStyle),
            _ => TextSpan(text: piece.char, style: around),
          });
        }
      }
      lineRuns(data, chars, para, from, end, children, underlined: underlined);
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

  static final Paint _clear = Paint()..color = const Color(0x00000000);

  /// The placeholder of the room over a page edge ([FlowBreak.gap] tall).
  static InlineSpan roomSpan(double gap) => WidgetSpan(
    alignment: PlaceholderAlignment.bottom,
    child: SizedBox(width: 0, height: gap < 0 ? 0 : gap),
  );

  /// The placeholder of paragraph spacing: from the baseline [height]
  /// down, no wider than nothing (see `TextSpacing`).
  static InlineSpan spacingSpan(double height) => WidgetSpan(
    alignment: PlaceholderAlignment.belowBaseline,
    baseline: TextBaseline.alphabetic,
    child: SizedBox(width: 0, height: height),
  );

  /// The line break after [roomSpan]: so small the line is as tall as the
  /// room.
  static const TextStyle _roomStyle = TextStyle(
    inherit: false,
    fontSize: 0.01,
    height: 1,
    color: Color(0x00000000),
  );

  /// The placeholder of a gap or padding ([size]).
  static InlineSpan gapSpan(Size size) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: SizedBox.fromSize(size: size),
  );

  /// Adds the runs of text [start, end) (within one line, formatted as
  /// [para]) to [out]; [underlined] (model offsets) is underlined.
  static void lineRuns(
    TextData data,
    List<SpanStyle> chars,
    ParaStyle para,
    int start,
    int end,
    List<InlineSpan> out, {
    TextRange underlined = TextRange.empty,
  }) {
    bool under(int i) => underlined.isValid && i >= underlined.start && i < underlined.end;
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
      out.add(TextSpan(text: data.text.substring(i, j), style: style));
      i = j;
    }
  }

  /// A laid-out [TextBoxLayout] of [data] in a box [width] wide. The
  /// caller disposes it.
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
    final width = naturalWidthOf(layout);
    layout.dispose();
    return width;
  }

  /// [naturalWidth] of text laid out without a width limit.
  static double naturalWidthOf(TextBoxLayout unbounded) {
    final w = (unbounded.painter.maxIntrinsicWidth + autoWidthSlack).ceilToDouble();
    return w < minWidth ? minWidth : w;
  }
}

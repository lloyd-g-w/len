import 'package:flutter/widgets.dart';

import '../../domain/text/text_data.dart';
import 'text_layout.dart';

/// [TextLayout] of one text box: a laid-out painter plus its list markers
/// and the hanging indents of wrapped list items ([wraps]).
class TextBoxLayout {
  TextBoxLayout(this.data, double width)
    : markers = TextLayout.markersOf(data),
      wraps = TextWraps.of(data, width) {
    offsets = MarkerOffsets(data, wraps);
    // Only the placeholders' sizes matter here; markers are painted
    // separately, gaps stay empty.
    final sizes = <Size>[];
    final span = TextLayout.spanOf(
      data,
      wraps: wraps,
      marker: (m) {
        _markerSlots.add(sizes.length);
        sizes.add(m.size);
        return const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox.shrink());
      },
      gap: (size) {
        sizes.add(size);
        return const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox.shrink());
      },
    );
    painter = TextPainter(
      // An empty box still has one line's height.
      text: span.children!.isEmpty ? TextSpan(text: ' ', style: span.style) : span,
      textAlign: TextLayout.alignOf(data),
      textDirection: TextDirection.ltr,
    );
    painter.setPlaceholderDimensions([
      for (final s in sizes) PlaceholderDimensions(size: s, alignment: PlaceholderAlignment.middle),
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

  /// Model offsets where wrapped list items continue (see [TextWraps]).
  final List<int> wraps;

  /// Model ↔ laid-out offsets of [painter]'s text.
  late final MarkerOffsets offsets;

  /// Indexes of the markers among the painter's placeholders.
  final List<int> _markerSlots = [];

  double get height => painter.height;

  /// The placeholder box of each of [markers] (local coordinates).
  List<Rect> get markerBoxes {
    final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
    return [
      for (final i in _markerSlots)
        if (i < boxes.length) boxes[i].toRect(),
    ];
  }

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

import 'dart:math' as math;
import 'dart:ui';

import '../../domain/text/text_data.dart';
import '../fonts/text_fonts.dart';
import 'text_layout.dart';

/// A committed text box laid out as it is drawn in its frame [Size].
///
/// A box's frame was measured in its fonts on the device that wrote it.
/// Where one of them is missing ([TextFonts.isShown]: an imported font not
/// on this device) the text is laid out in the fallback font, which wraps
/// differently and may need more height than the frame has. Such a layout
/// is fitted into the frame for display only (UX_AUDIT R26-30): laid out
/// wider and drawn scaled down by [scale], so it fills the frame's width
/// and never runs past its bottom (nor past its selection outline or hit
/// area, which stay the frame). The stored data and frame are unchanged;
/// once the font arrives the box is drawn at full size again.
///
/// A box whose frame cuts a table row (a row taller than a page, cut at the
/// page's end: `TextFlowLayout`) is drawn [clipped] to its frame, the cut
/// row fading out above a dashed line: the row goes on (UX_AUDIT R26-14).
class ShownTextLayout {
  ShownTextLayout._(this.layout, this.scale, {this.clipped});

  /// [data] laid out for a frame of [frame] size.
  factory ShownTextLayout.of(TextData data, Size frame) {
    final layout = TextLayout.layout(data, frame.width);
    if (cutRow(layout, frame.height) case final row?) {
      return ShownTextLayout._(layout, 1, clipped: (frame: Offset.zero & frame, row: row));
    }
    if (layout.height <= frame.height + _slack || !lacksFont(data) || frame.height <= 0) {
      return ShownTextLayout._(layout, 1);
    }
    // Laid out at width w / s, the text is no taller than at w, so drawn
    // at s it fits: s × height(w / s) ≤ s × height(w) = frame height.
    var s = frame.height / layout.height;
    layout.dispose();
    final wider = TextLayout.layout(data, frame.width / s);
    s = math.min(s, frame.height / wider.height);
    return ShownTextLayout._(wider, s);
  }

  /// Rounding the frame's height may leave it a hair short of the text.
  static const double _slack = 0.5;

  /// The layout, in its own coordinates ([toLayout]).
  final TextBoxLayout layout;

  /// How much smaller than [layout] the text is drawn (1: as laid out).
  final double scale;

  /// The frame the text is clipped to (local coordinates) and the row it
  /// cuts; null: the text fits its frame.
  final ({Rect frame, Rect row})? clipped;

  /// The table row of [layout] that a frame [height] tall cuts (by more
  /// than a rounding error), if any.
  static Rect? cutRow(TextBoxLayout layout, double height) {
    if (layout.height <= height + _slack) return null;
    for (final r in layout.rows) {
      if (r.rect.top < height && r.rect.bottom > height + _slack) return r.rect;
    }
    return null;
  }

  /// Whether [data] uses a font that is not shown here (its box's or a
  /// span's), so it is laid out in the fallback font.
  static bool lacksFont(TextData data) =>
      !TextFonts.isShown(data.font) ||
      data.spans.any((s) => s.style.font != null && !TextFonts.isShown(s.style.font!));

  /// Point [local] in the frame (top left 0, 0) in [layout]'s coordinates.
  Offset toLayout(Offset local) => local / scale;

  /// Paints the text with the frame's top left at [origin].
  void paint(Canvas canvas, Offset origin) {
    if (clipped case final c?) return _paintClipped(canvas, origin, c.frame, c.row);
    if (scale == 1) return layout.paint(canvas, origin);
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(scale);
    layout.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// Paints the text clipped to [frame], the cut [row] fading out toward
  /// the frame's bottom, where a dashed line in the grid's colour closes
  /// it (the row goes on: shown whole when edited).
  void _paintClipped(Canvas canvas, Offset origin, Rect frame, Rect row) {
    final box = frame.shift(origin);
    final data = layout.data;
    final fade = math.min(data.fontSize * 1.5, box.height / 3);
    canvas
      ..save()
      ..clipRect(box)
      ..saveLayer(box, Paint());
    layout.paint(canvas, origin);
    final band = Rect.fromLTRB(box.left, box.bottom - fade, box.right, box.bottom);
    canvas
      ..drawRect(
        band,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = Gradient.linear(band.topCenter, band.bottomCenter, [
            const Color(0x00000000),
            const Color(0xCC000000),
          ]),
      )
      ..restore()
      ..restore();
    final line = Paint()
      ..color = TableLayout.gridColorOf(data)
      ..strokeWidth = TableLayout.lineWidthOf(data) * 2;
    final dash = data.fontSize / 4;
    final y = box.bottom - line.strokeWidth / 2;
    final left = origin.dx + row.left, right = origin.dx + row.right;
    for (var x = left; x < right; x += 2 * dash) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, right), y), line);
    }
  }

  void dispose() => layout.dispose();
}

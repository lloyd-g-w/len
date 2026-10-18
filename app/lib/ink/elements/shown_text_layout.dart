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
class ShownTextLayout {
  ShownTextLayout._(this.layout, this.scale);

  /// [data] laid out for a frame of [frame] size.
  factory ShownTextLayout.of(TextData data, Size frame) {
    final layout = TextLayout.layout(data, frame.width);
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

  /// Whether [data] uses a font that is not shown here (its box's or a
  /// span's), so it is laid out in the fallback font.
  static bool lacksFont(TextData data) =>
      !TextFonts.isShown(data.font) ||
      data.spans.any((s) => s.style.font != null && !TextFonts.isShown(s.style.font!));

  /// Point [local] in the frame (top left 0, 0) in [layout]'s coordinates.
  Offset toLayout(Offset local) => local / scale;

  /// Paints the text with the frame's top left at [origin].
  void paint(Canvas canvas, Offset origin) {
    if (scale == 1) return layout.paint(canvas, origin);
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(scale);
    layout.paint(canvas, Offset.zero);
    canvas.restore();
  }

  void dispose() => layout.dispose();
}

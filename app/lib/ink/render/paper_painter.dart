import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../domain/paper.dart';
import '../../domain/paper_pattern.dart';
import '../viewport.dart';

/// Colours around the paper. The paper itself and its pattern come from
/// [PaperColor]; paper keeps its colour in dark mode, like real paper.
class PaperColors {
  const PaperColors({
    this.margin = const Color(0x66E86A6A),
    this.desk = const Color(0xFFE9EAEE),
    this.shadow = const Color(0x33000000),
  });

  /// The red margin line of ruled paper.
  final Color margin;

  /// Background around pages.
  final Color desk;
  final Color shadow;
}

/// Looks up a decoded image template ([PaperStyle.image]) to draw about
/// [pixelWidth] device pixels wide; null while it is not decoded yet.
typedef PaperImageLookup = ui.Image? Function(String blob, double pixelWidth);

/// Draws paper sheets and their templates in world coordinates, for any
/// target: the editor, thumbnails and raster export.
abstract final class PaperRenderer {
  /// Below this on-screen pitch repeating lines are hidden (they would be
  /// noise); structure (sections, frames, labels) stays.
  static const double minScreenSpacing = 7;

  /// The smallest on-screen pitch drawn in miniatures.
  static const double minMiniatureSpacing = 1.5;

  static double _threshold(PaperStyle style) => switch (style) {
    // Staves are dense by design; dots are counted per area, not per line.
    PaperStyle.music => minScreenSpacing / 2,
    PaperStyle.dotted => minScreenSpacing * 2,
    _ => minScreenSpacing,
  };

  /// Fills [page] with the paper colour, with a soft drop shadow.
  static void paintSheet(
    Canvas canvas,
    Rect page,
    PaperColor color, {
    required double scale,
    PaperColors colors = const PaperColors(),
    bool shadow = true,
  }) {
    if (shadow) {
      canvas.drawRect(
        page.shift(Offset(0, 2 / scale)),
        Paint()
          ..color = colors.shadow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 / scale),
      );
    }
    canvas.drawRect(page, Paint()..color = color.paper);
  }

  /// Draws the template [paper] within [area] (world units). The canvas
  /// must already map world units to device pixels at [scale]. Repeating
  /// lines too dense to read are skipped; [always] (miniature previews)
  /// keeps them down to [minMiniatureSpacing]. Image templates are drawn
  /// over [page] from [images] once decoded.
  static void paintPattern(
    Canvas canvas,
    Paper paper,
    PaperColor color,
    Rect area, {
    Rect? page,
    required double scale,
    PaperColors colors = const PaperColors(),
    bool always = false,
    PaperImageLookup? images,
  }) {
    final style = paper.style;
    if (style == PaperStyle.blank && !paper.look.header) return;
    if (style == PaperStyle.image) {
      final blob = paper.image;
      final image = page == null || blob == null ? null : images?.call(blob, page.width * scale);
      if (image != null) _paintImage(canvas, image, page!);
      return;
    }
    final minPitch = (always ? minMiniatureSpacing : _threshold(style)) / scale;
    final pattern = PaperPattern.of(paper, area, page: page, minPitch: minPitch);
    if (pattern.isEmpty) return;
    final look = paper.look;
    final ink = look.patternOn(color.pattern);
    for (final f in pattern.fills) {
      canvas.drawRect(f.rect, Paint()..color = ink.withValues(alpha: ink.a * f.opacity));
    }
    // One device pixel in world units (thinner in miniatures), times the
    // look's weight.
    final px = (always ? math.min(1.0, 0.5 + scale) : 1) / scale * look.lineWeight;
    for (final weight in PatternWeight.values) {
      final points = <Offset>[
        for (final l in pattern.lines)
          if (l.weight == weight) ...[l.a, l.b],
      ];
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = switch (weight) {
          PatternWeight.margin => colors.margin,
          PatternWeight.fine => ink.withValues(alpha: ink.a * 0.6),
          PatternWeight.normal => ink,
          PatternWeight.heavy => heavyColor(ink, color),
        }
        ..strokeWidth = switch (weight) {
          PatternWeight.fine => 0.7 * px,
          PatternWeight.normal => px,
          PatternWeight.heavy => 1.6 * px,
          PatternWeight.margin => 1.5 * px,
        };
      canvas.drawPoints(ui.PointMode.lines, points, paint);
    }
    if (pattern.dots.isNotEmpty) {
      final radius =
          math.max(1.0, 1.4 * math.min(1.0, scale)) * px / look.lineWeight * look.dotSize;
      canvas.drawPoints(
        ui.PointMode.points,
        pattern.dots,
        Paint()
          ..color = ink
          ..strokeWidth = radius * 2
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final label in pattern.labels) {
      // Text smaller than ~3 device pixels is unreadable: skip it (keep it
      // as texture in miniatures).
      if (label.size * scale < (always ? 1.2 : 3)) continue;
      PatternText.paint(
        canvas,
        label,
        label.muted ? color.text.withValues(alpha: PatternLabel.mutedOpacity) : color.text,
      );
    }
  }

  /// Structural lines: the pattern colour [ink] a little towards the
  /// paper's text colour.
  static Color heavyColor(Color ink, PaperColor color) {
    final heavy = Color.lerp(ink.withValues(alpha: 1), color.text, 0.22)!;
    return heavy.withValues(alpha: ink.a);
  }

  static void _paintImage(Canvas canvas, ui.Image image, Rect page) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      page,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}

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

/// Paints the paper background and its pattern for the visible area only,
/// so an infinite canvas costs the same as a single page.
class PaperPainter extends CustomPainter {
  /// Draws [paper], or else a [style] without parameters.
  PaperPainter({
    required this.viewport,
    PaperStyle style = PaperStyle.blank,
    Paper? paper,
    this.paperColor = PaperColor.white,
    this.page,
    this.colors = const PaperColors(),
    this.images,
  }) : paper = paper ?? Paper(style),
       super(repaint: viewport);

  final ViewportController viewport;
  final Paper paper;
  final PaperColor paperColor;

  /// Decoded image templates.
  final PaperImageLookup? images;

  /// Page rectangle in world units, or null for an infinite canvas.
  final Rect? page;
  final PaperColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = viewport.visibleWorldFor(size);
    final scale = viewport.scale;
    if (page == null) canvas.drawRect(Offset.zero & size, Paint()..color = paperColor.paper);
    if (page != null) canvas.drawRect(Offset.zero & size, Paint()..color = colors.desk);
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(scale);
    final area = page == null ? visible : visible.intersect(page!);
    if (page != null) {
      PaperRenderer.paintSheet(canvas, page!, paperColor, scale: scale, colors: colors);
    }
    if (!area.isEmpty) {
      canvas.clipRect(area);
      PaperRenderer.paintPattern(
        canvas,
        paper,
        paperColor,
        area,
        page: page,
        scale: scale,
        colors: colors,
        images: images,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.viewport != viewport ||
      old.paper != paper ||
      old.images != images ||
      old.paperColor != paperColor ||
      old.page != page ||
      old.colors != colors;
}

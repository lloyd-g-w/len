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
    this.desk = const Color(0xFFE6E6E6),
    this.shadow = const Color(0x33000000),
  });

  /// The red margin line of ruled paper.
  final Color margin;

  /// Background around pages: by default the light Desk tone (a true
  /// grey, DESIGN §1); the editor passes the theme's.
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

  /// Below this scale page thumbnails strengthen their pattern (fully from
  /// [faintScaleFull] down), so faint dots and fine rulings still read in
  /// page thumbnails rather than dropping out to look blank.
  static const double faintScale = 0.5, faintScaleFull = 0.2;

  /// The thinnest pattern line (and the smallest dot radius) in a page
  /// thumbnail, in screen pixels.
  static const double minMiniatureLine = 1, minMiniatureDot = 0.8;

  /// The width of a pattern line of [weight] in world units (× the look's
  /// line weight): what PDF export prints (0.3, 0.5 and 0.9 pt), drawn the
  /// same on the page at every zoom.
  static double lineWidth(PatternWeight weight) => switch (weight) {
    PatternWeight.fine => 0.4,
    PatternWeight.normal => 2 / 3,
    PatternWeight.heavy || PatternWeight.margin => 1.2,
  };

  /// The thinnest a line is drawn, in target pixels (logical pixels on
  /// screen, one device pixel on a 2× tablet): thinner lines fade instead.
  static const double minLineWidth = 0.5;

  /// The radius of a paper dot in world units (× the look's dot size):
  /// 0.37 mm, printed as drawn on screen, at every zoom.
  static const double dotRadius = 1.4;

  /// The smallest radius a dot is drawn at, in target pixels (logical
  /// pixels on screen, about one device pixel across on a tablet): dots
  /// smaller on screen fade instead of shrinking into sub-pixel noise.
  static const double minDotRadius = 0.5;

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
  /// keeps them down to [minMiniatureSpacing]; a [thumbnail] of a page
  /// also strengthens them when small. Image templates are drawn
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
    bool thumbnail = false,
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
    // Staves are structure: they stay as grey bands in thumbnails and
    // template miniatures (they read as music).
    final mini = always || thumbnail;
    final miniPitch = style == PaperStyle.music ? minMiniatureSpacing / 2 : minMiniatureSpacing;
    final minPitch = (mini ? miniPitch : _threshold(style)) / scale;
    final pattern = PaperPattern.of(paper, area, page: page, minPitch: minPitch);
    if (pattern.isEmpty) return;
    final look = paper.look;
    final faint = thumbnail ? _faintness(scale) : 0.0;
    final ink = _strengthen(look.patternOn(color.pattern), color, faint);
    for (final f in pattern.fills) {
      canvas.drawRect(f.rect, Paint()..color = ink.withValues(alpha: ink.a * f.opacity));
    }
    for (final weight in PatternWeight.values) {
      final points = <Offset>[
        for (final l in pattern.lines)
          if (l.weight == weight) ...[l.a, l.b],
      ];
      if (points.isEmpty) continue;
      final c = switch (weight) {
        PatternWeight.margin => colors.margin,
        PatternWeight.fine => ink.withValues(alpha: ink.a * (0.6 + 0.4 * faint)),
        PatternWeight.normal => ink,
        PatternWeight.heavy => heavyColor(ink, color),
      };
      final (width, fade) = _lineWidth(weight, look, scale, mini: mini, faint: faint);
      final paint = Paint()
        ..color = c.withValues(alpha: c.a * fade)
        ..strokeWidth = width / scale;
      canvas.drawPoints(ui.PointMode.lines, points, paint);
    }
    if (pattern.dots.isNotEmpty) {
      // Template miniatures show the pattern, not the page at a zoom.
      _paintDots(canvas, pattern.dots, ink, look, scale, always ? 1 : faint);
    }
    for (final label in pattern.labels) {
      // Text smaller than ~3 device pixels is unreadable: skip it (keep it
      // as texture in miniatures).
      if (label.size * scale < (mini ? 1.2 : 3)) continue;
      PatternText.paint(
        canvas,
        label,
        label.muted ? color.text.withValues(alpha: PatternLabel.mutedOpacity) : color.text,
      );
    }
  }

  /// Paints [dots] [dotRadius] × the look's dot size in world units, so
  /// they scale with the page and the ink. Smaller on screen than
  /// [minDotRadius] (far out), they stay that size and fade instead,
  /// keeping the ink a dot puts down (its area); a strengthened page
  /// thumbnail ([faint]; 1 for template miniatures) keeps them at least
  /// [minMiniatureDot], unfaded.
  static void _paintDots(
    Canvas canvas,
    List<Offset> dots,
    Color ink,
    PaperLook look,
    double scale,
    double faint,
  ) {
    final shown = dotRadius * look.dotSize * scale;
    final floor = math.max(minDotRadius, minMiniatureDot * faint);
    final fade = shown >= floor ? 1.0 : ui.lerpDouble(math.pow(shown / floor, 2), 1, faint)!;
    canvas.drawPoints(
      ui.PointMode.points,
      dots,
      Paint()
        ..color = ink.withValues(alpha: ink.a * fade)
        ..strokeWidth = 2 * math.max(shown, floor) / scale
        ..strokeCap = StrokeCap.round,
    );
  }

  /// The target-pixel width and the opacity of a [weight] line at [scale].
  /// On the page it is [lineWidth] × the look's weight, so it scales with
  /// the page and the ink; thinner than [minLineWidth] (far out) it stays
  /// that wide and fades by the width it lost, keeping its ink. Miniatures
  /// ([mini]) keep their lines about a pixel wide (in the weights'
  /// proportions), unfaded; a strengthened page thumbnail ([faint]) at
  /// least [minMiniatureLine].
  static (double, double) _lineWidth(
    PatternWeight weight,
    PaperLook look,
    double scale, {
    required bool mini,
    required double faint,
  }) {
    final shown = lineWidth(weight) * look.lineWeight * scale;
    if (mini) {
      final relative = lineWidth(weight) / lineWidth(PatternWeight.normal) * look.lineWeight;
      final floor = math.min(1.0, 0.5 + scale) * relative;
      return (math.max(shown, math.max(floor, minMiniatureLine * faint)), 1);
    }
    if (shown >= minLineWidth) return (shown, 1);
    return (minLineWidth, shown / minLineWidth);
  }

  /// How much a page thumbnail at [scale] strengthens its pattern: 0 from
  /// [faintScale] up, 1 from [faintScaleFull] down.
  static double _faintness(double scale) =>
      ((faintScale - scale) / (faintScale - faintScaleFull)).clamp(0.0, 1.0);

  /// The pattern colour [ink] moved towards the paper's text colour (and
  /// made more opaque) by [faint], for contrast at small sizes.
  static Color _strengthen(Color ink, PaperColor color, double faint) {
    if (faint == 0) return ink;
    final darker = Color.lerp(ink.withValues(alpha: 1), color.text, 0.2 * faint)!;
    return darker.withValues(alpha: ink.a + (1 - ink.a) * 0.3 * faint);
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
    this.miniature = false,
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

  /// A page thumbnail: dense patterns stay (strengthened when small)
  /// rather than hidden.
  final bool miniature;

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
        thumbnail: miniature,
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
      old.colors != colors ||
      old.miniature != miniature;
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where the zoom window writes: a rectangle on one surface (a page, or
/// the infinite canvas) shown magnified in the box at the bottom of the
/// screen. Its size follows from the box: `box / scale`.
@immutable
class ZoomFrame {
  const ZoomFrame({required this.surfaceId, required this.origin, required this.scale});

  /// The page (or canvas) the frame lies on.
  final String surfaceId;

  /// The frame's top-left corner, in the surface's coordinates.
  final Offset origin;

  /// Box pixels per surface unit: how much the box magnifies.
  final double scale;

  /// The frame on its surface when the box is [box] large.
  Rect rectFor(Size box) => origin & (box / scale);

  ZoomFrame copyWith({String? surfaceId, Offset? origin, double? scale}) => ZoomFrame(
    surfaceId: surfaceId ?? this.surfaceId,
    origin: origin ?? this.origin,
    scale: scale ?? this.scale,
  );

  @override
  bool operator ==(Object other) =>
      other is ZoomFrame &&
      other.surfaceId == surfaceId &&
      other.origin == origin &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(surfaceId, origin, scale);

  @override
  String toString() => 'ZoomFrame($surfaceId, $origin, ×$scale)';
}

/// What the frame does after ink reached the advance zone, or after a new
/// line was asked for.
sealed class ZoomMove {
  const ZoomMove();
}

/// The frame moves on the same surface.
class ZoomMoveTo extends ZoomMove {
  const ZoomMoveTo(this.origin);
  final Offset origin;
}

/// The frame goes on to the next page, at [origin] there.
class ZoomNextPage extends ZoomMove {
  const ZoomNextPage(this.origin);
  final Offset origin;
}

/// The rules of the zoom window: where the frame may be, when and how far
/// it advances along a line, and how it wraps to the next line or page.
/// Pure geometry (surface coordinates), so it is tested on its own.
///
/// A line runs from [lineStart] (where the frame was put) to [lineEnd]
/// (the page's right edge; on a canvas, the right edge of the view when
/// the line began). Ink lifted in the right [advanceZone] of the frame
/// moves the frame on so that ink sits [keep] into it; once the frame
/// stands at the end of the line, it wraps: back to [lineStart], down by a
/// line. At the bottom of a page it goes on to the next page's top.
class ZoomRules {
  const ZoomRules({required this.box, required this.lineStart, required this.lineEnd, this.page});

  /// The box's size (screen pixels).
  final Size box;

  /// The page's bounds (surface coordinates), or null on a canvas.
  final Rect? page;

  /// Where lines begin and end (surface x).
  final double lineStart, lineEnd;

  /// The right part of the frame (a fraction of its width) where lifted
  /// ink advances the frame.
  static const double advanceZone = 0.3;

  /// Ink lifted this far across the frame advances it at once (no pause).
  static const double advanceNow = 0.9;

  /// After advancing, the last ink sits this far into the frame (a
  /// fraction of its width), so the word in progress stays in view.
  static const double keep = 0.25;

  /// Ends of a page the frame keeps clear of when it starts a page
  /// (fraction of the page's height).
  static const double topMargin = 0.04;

  /// Smallest and largest frame width, as a fraction of a page's width.
  static const double minPageFraction = 0.12, maxPageFraction = 1;

  /// The narrowest frame on a canvas (surface units).
  static const double minCanvasWidth = 24;

  /// How many ruled lines (or grid rows) the box shows when it opens.
  static const double linesShown = 3;

  /// The frame's width when the window opens, as a fraction of a page's
  /// width (or of the main view's on a canvas without lines).
  static const double startFraction = 1 / 3, minStartFraction = 0.2, maxStartFraction = 0.6;

  /// The magnification the window opens with: [linesShown] lines of
  /// [pitch] fill the box's height, so letters written at a comfortable
  /// size in the box land on the paper's lines; without lines, a third of
  /// the page (or of [viewWidth], the main view's width on a canvas).
  double startScale({double? pitch, required double viewWidth}) {
    final page = this.page;
    var width = pitch != null && pitch > 0 && !box.isEmpty
        ? box.width * pitch * linesShown / box.height
        : (page?.width ?? viewWidth) * startFraction;
    if (page != null) {
      width = width.clamp(page.width * minStartFraction, page.width * maxStartFraction);
    }
    return box.width / math.max(minCanvasWidth, width);
  }

  /// Where the advance zone begins on the surface.
  double zoneStart(ZoomFrame frame) {
    final rect = frame.rectFor(box);
    return rect.left + rect.width * (1 - advanceZone);
  }

  /// Whether ink ending at [inkRight] lies in the advance zone.
  bool inZone(ZoomFrame frame, double inkRight) => inkRight >= zoneStart(frame);

  /// Whether ink ending at [inkRight] advances the frame without a pause.
  bool advancesNow(ZoomFrame frame, double inkRight) {
    final rect = frame.rectFor(box);
    return inkRight >= rect.left + rect.width * advanceNow;
  }

  /// [frame] moved to [origin], kept on the page (centred on an axis the
  /// page is narrower than the frame along).
  Offset clamp(ZoomFrame frame, Offset origin) {
    final page = this.page;
    if (page == null) return origin;
    final size = box / frame.scale;
    double axis(double v, double start, double end, double extent) =>
        extent >= end - start ? start + (end - start - extent) / 2 : v.clamp(start, end - extent);
    return Offset(
      axis(origin.dx, page.left, page.right, size.width),
      axis(origin.dy, page.top, page.bottom, size.height),
    );
  }

  /// The scale that shows [width] surface units across the box, within
  /// the limits a page sets ([minPageFraction], [maxPageFraction]).
  double scaleForWidth(double width) {
    final page = this.page;
    var w = width;
    if (page != null) {
      w = w.clamp(page.width * minPageFraction, page.width * maxPageFraction);
    }
    return box.width / math.max(1, w);
  }

  /// Where the frame goes once ink lifted at [inkRight] in the zone: on
  /// along the line, or (at its end) to the next line, [lineStep] down.
  ZoomMove advance(ZoomFrame frame, double inkRight, {required double lineStep}) {
    final width = box.width / frame.scale;
    final end = math.max(lineEnd - width, lineStart);
    // Already at the end of the line (give or take a little): wrap.
    if (frame.origin.dx >= end - width * 0.05) return newLine(frame, lineStep: lineStep);
    final left = math.min(inkRight - width * keep, end);
    if (left <= frame.origin.dx) return ZoomMoveTo(frame.origin);
    return ZoomMoveTo(clamp(frame, Offset(left, frame.origin.dy)));
  }

  /// The start of the next line, [lineStep] below; past the bottom of a
  /// page, the top of the next one.
  ZoomMove newLine(ZoomFrame frame, {required double lineStep}) {
    final page = this.page;
    final top = frame.origin.dy + lineStep;
    if (page == null) return ZoomMoveTo(Offset(lineStart, top));
    final height = box.height / frame.scale;
    final bottom = page.bottom - height;
    if (frame.origin.dy >= bottom - 0.5) {
      final next = Offset(lineStart, page.top + page.height * topMargin);
      return ZoomNextPage(clamp(frame, next));
    }
    return ZoomMoveTo(clamp(frame, Offset(lineStart, math.min(top, bottom))));
  }

  /// How far a new line moves down: whole ruled lines (or grid rows) of
  /// [pitch] as tall as the line's ink ([inkHeight], descenders allowed
  /// for), or else a third of the frame per line of ink.
  static double lineStep({required double frameHeight, required double inkHeight, double? pitch}) {
    final unit = pitch != null && pitch > 0 ? pitch : frameHeight / 3;
    final lines = math.max(1, (inkHeight / unit + 0.3).floor());
    return unit * lines;
  }
}

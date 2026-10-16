// Mouse ink written zoomed out is as smooth on screen as at 100 %: mouse
// positions are whole pixels, a staircase the outline's smoothing (relative
// to the pen's width) levels only while the pen is wide enough on screen;
// `MouseSmoother` makes up the rest, and leaves wide enough pens alone.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/mouse_smoother.dart';
import 'package:len/ink/input/stroke_sampler.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/viewport.dart';

/// A smooth path on screen (px): a wave with loops of cursive size, t in 0..1.
Offset _curve(double t) => Offset(
  40 + 500 * t + 25 * math.sin(t * 2 * math.pi * 5),
  200 - 60 * math.sin(t * math.pi * 2) - 30 * (1 - math.cos(t * 2 * math.pi * 5)),
);

/// Mouse events along [_curve], one every [spacing] px, at whole pixels.
List<Offset> _mouse(double spacing) {
  var last = _curve(0);
  final out = [Offset(last.dx.roundToDouble(), last.dy.roundToDouble())];
  for (var t = 0.0; t < 1; t += 0.00005) {
    final p = _curve(t);
    if ((p - last).distance < spacing) continue;
    out.add(Offset(p.dx.roundToDouble(), p.dy.roundToDouble()));
    last = p;
  }
  return out;
}

/// The smoothed centre line of [screen] samples written at [zoom] with a
/// pen [width] world units wide and stabiliser [streamline], in screen px.
List<Offset> _inked(
  List<Offset> screen,
  double zoom,
  double width,
  double streamline, {
  bool smooth = true,
}) {
  final viewport = ViewportController(minScale: 0.01)
    ..setSize(const Size(800, 600))
    ..zoomAt(Offset.zero, zoom);
  final first = viewport.toWorld(screen.first);
  final points = [StrokePoint(first.dx, first.dy, 0.5)];
  final sampler = StrokeSampler(viewport, (from, at, p, ms) => points.add(p));
  var last = screen.first;
  void sample(Offset at, int ms) {
    if (sampler.add(last, at, 0.5, ms)) last = at;
  }

  final smoother = MouseSmoother(sample)..begin(screen.first, 0, width: width * zoom);
  for (var i = 1; i < screen.length; i++) {
    smooth ? smoother.add(screen[i], i * 8) : sample(screen[i], i * 8);
  }
  if (smooth) smoother.finish();
  final spec = OutlineSpec(width: width, thinning: 0, streamline: streamline, unit: 1 / zoom);
  final c = StrokeOutline.centerline(points, spec)!;
  return [for (var i = 0; i < c.length; i++) Offset(c.x[i] * zoom, c.y[i] * zoom)];
}

/// How much the line's turning changes along it, sampled every 2 px
/// (radians): a smooth curve's is small, a wobbly one's large.
double _wobble(List<Offset> line) {
  final even = [line.first];
  var run = 0.0;
  for (var i = 1; i < line.length; i++) {
    run += (line[i] - line[i - 1]).distance;
    if (run < 2) continue;
    even.add(line[i]);
    run = 0;
  }
  var sum = 0.0;
  double? previous;
  for (var i = 1; i + 1 < even.length; i++) {
    final a = even[i] - even[i - 1], b = even[i + 1] - even[i];
    final turn = math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy);
    if (previous != null) sum += (turn - previous).abs();
    previous = turn;
  }
  return sum;
}

/// The mouse's true path, densely sampled (px), as x, y pairs.
final Float64List _truth = Float64List.fromList([
  for (var t = 0.0; t <= 1; t += 0.0005) ...[_curve(t).dx, _curve(t).dy],
]);

/// The farthest [line] strays from the mouse's true path (px).
double _deviation(List<Offset> line) {
  var worst = 0.0;
  for (final p in line) {
    var best = double.infinity;
    for (var i = 0; i < _truth.length; i += 2) {
      final dx = _truth[i] - p.dx, dy = _truth[i + 1] - p.dy;
      best = math.min(best, dx * dx + dy * dy);
    }
    worst = math.max(worst, best);
  }
  return math.sqrt(worst);
}

void main() {
  for (final spacing in [2.0, 4.0]) {
    test('mouse events every $spacing px: as smooth at any zoom as at 100 %', () {
      final mouse = _mouse(spacing);
      // The default pen at 100 %, which the outline alone smooths: the
      // reference.
      final full = _wobble(_inked(mouse, 1, 2.5, 0, smooth: false));
      for (final streamline in [0.0, 0.5, 1.0]) {
        final drift = _deviation(_inked(mouse, 1, 2.5, streamline, smooth: false));
        // Thin to thick pens, the highlighter's narrowest.
        for (final width in [0.5, 2.5, 4.0, 12.0]) {
          for (final zoom in [1.0, 0.5, 0.25, 0.1]) {
            final line = _inked(mouse, zoom, width, streamline);
            final wobble = _wobble(line);
            final reason = 'width $width, zoom $zoom, stabiliser $streamline: $wobble vs $full';
            expect(wobble, lessThan(full * 1.15), reason: reason);
            // Smooth, not distorted: it follows the path the hand made
            // about as closely as before (smoothing rounds the tightest
            // turns a little).
            expect(_deviation(line), lessThan(drift + 1), reason: reason);
          }
        }
      }
    });
  }

  test('without levelling, zoomed out mouse ink was squiggly (the bug)', () {
    final mouse = _mouse(2);
    final full = _wobble(_inked(mouse, 1, 2.5, 0.5, smooth: false));
    final out = _wobble(_inked(mouse, 0.25, 2.5, 0.5, smooth: false));
    expect(out, greaterThan(full * 3));
  });

  test('a pen at least 2.5 px wide on screen: the mouse passes on unchanged, without lag', () {
    final mouse = _mouse(3);
    for (final width in [MouseSmoother.fullWidth, 12.0]) {
      final kept = <Offset>[];
      final smoother = MouseSmoother((at, _) => kept.add(at))..begin(mouse.first, 0, width: width);
      for (var i = 1; i < mouse.length; i++) {
        smoother.add(mouse[i], i * 8);
        expect(kept.last, mouse[i]);
      }
      smoother.finish();
      expect(kept, mouse.sublist(1));
    }
  });

  test('the smoothing grows as the pen thins on screen', () {
    expect(MouseSmoother.sigmaFor(2.5), 0);
    expect(MouseSmoother.sigmaFor(1.25), inExclusiveRange(1, 2));
    expect(MouseSmoother.sigmaFor(0), MouseSmoother.maxSigma);
    expect(MouseSmoother.reachOf(MouseSmoother.maxSigma), 6);
  });

  test('the smoothed stroke starts and ends where the mouse went down and up', () {
    final mouse = _mouse(3);
    final kept = <Offset>[];
    final smoother = MouseSmoother((at, _) => kept.add(at))..begin(mouse.first, 0, width: 0);
    final reach = MouseSmoother.reachOf(MouseSmoother.maxSigma);
    for (var i = 1; i < mouse.length; i++) {
      smoother.add(mouse[i], i * 8);
      // It trails the mouse by at most its reach (plus a resampling step).
      if (kept.isNotEmpty) {
        expect((kept.last - mouse[i]).distance, lessThan(reach + 3 + 1e-9));
      }
    }
    smoother.finish();
    expect(kept.last, mouse.last);
    expect((kept.first - mouse.first).distance, lessThanOrEqualTo(MouseSmoother.spacing + 1e-9));
  });

  test('a flush catches up with a resting mouse, and smoothing carries on after it', () {
    final mouse = _mouse(3);
    final kept = <Offset>[];
    final smoother = MouseSmoother((at, _) => kept.add(at))..begin(mouse.first, 0, width: 0);
    final half = mouse.length ~/ 2;
    for (var i = 1; i <= half; i++) {
      smoother.add(mouse[i], i * 8);
    }
    smoother.flush();
    expect(kept.last, mouse[half]);
    final flushed = kept.length;
    for (var i = half + 1; i < mouse.length; i++) {
      smoother.add(mouse[i], i * 8);
    }
    smoother.finish();
    expect(kept.length, greaterThan(flushed));
    expect(kept.last, mouse.last);
    // No point goes back over the flushed end.
    expect((kept[flushed] - mouse[half]).distance, lessThanOrEqualTo(MouseSmoother.spacing + 1e-9));
  });
}

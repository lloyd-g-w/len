// Mouse ink written zoomed out is as smooth on screen as at 100 %: mouse
// positions are whole pixels, and the outline's smoothing must work at the
// zoom the stroke is written at, however thin the pen is on screen
// (`StrokeOutline.unitOf`).
import 'dart:math' as math;
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

  final smoother = MouseSmoother(sample)..begin(screen.first, 0);
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

/// The farthest [line] strays from the mouse's true path (px).
double _deviation(List<Offset> line) {
  final truth = [for (var t = 0.0; t <= 1; t += 0.0005) _curve(t)];
  var worst = 0.0;
  for (final p in line) {
    var best = double.infinity;
    for (final q in truth) {
      best = math.min(best, (q - p).distance);
    }
    worst = math.max(worst, best);
  }
  return worst;
}

void main() {
  for (final spacing in [2.0, 4.0]) {
    test('mouse events every $spacing px: as smooth at any zoom as at 100 %', () {
      final mouse = _mouse(spacing);
      // What 100 % gave before the steps were levelled: the reference.
      final before = _wobble(_inked(mouse, 1, 2.5, 0, smooth: false));
      final full = _wobble(_inked(mouse, 1, 2.5, 0));
      expect(full, lessThan(before / 2), reason: 'smoother than before at 100 %');
      for (final streamline in [0.0, 0.5, 1.0]) {
        final drift = _deviation(_inked(mouse, 1, 2.5, streamline, smooth: false));
        for (final zoom in [1.0, 0.5, 0.25, 0.1]) {
          final line = _inked(mouse, zoom, 2.5, streamline);
          final wobble = _wobble(line);
          final reason = 'zoom $zoom, stabiliser $streamline: $wobble vs $full at 100 %';
          expect(wobble, lessThan(full * 1.15), reason: reason);
          // Smooth, not distorted: it follows the path the hand made about
          // as closely as before (smoothing rounds the tightest turns a
          // little).
          expect(_deviation(line), lessThan(drift + 1), reason: reason);
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

  test('the smoothed stroke starts and ends where the mouse went down and up', () {
    final mouse = _mouse(3);
    final kept = <Offset>[];
    final smoother = MouseSmoother((at, _) => kept.add(at))..begin(mouse.first, 0);
    for (var i = 1; i < mouse.length; i++) {
      smoother.add(mouse[i], i * 8);
      // It trails the mouse by at most its reach (plus a resampling step).
      if (kept.isNotEmpty) {
        expect((kept.last - mouse[i]).distance, lessThan(MouseSmoother.reach + 3 + 1e-9));
      }
    }
    smoother.finish();
    expect(kept.last, mouse.last);
    expect((kept.first - mouse.first).distance, lessThanOrEqualTo(MouseSmoother.spacing + 1e-9));
  });
}

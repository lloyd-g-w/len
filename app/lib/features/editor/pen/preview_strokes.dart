import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/stroke.dart';

/// One cursive letter of [PreviewStrokes.word]: its height (of the line's
/// x-height, 1 = an `e`) and how wide its loop opens (0: an `u`).
typedef PreviewLetter = ({double height, double loop});

/// Sample strokes for the ink previews: a few words of joined-up
/// handwriting with the pressure of a real hand (heavier down-strokes,
/// light entries and exits), and a highlighter's pass. Deterministic.
abstract final class PreviewStrokes {
  static const PreviewLetter _e = (height: 1, loop: 2.5);
  static const PreviewLetter _l = (height: 2.3, loop: 2.1);
  static const PreviewLetter _u = (height: 1, loop: 0.4);

  /// The words written, as letters: reads like "lele uel".
  static const List<List<PreviewLetter>> words = [
    [_l, _e, _u, _e],
    [_e, _l, _l, _e],
  ];

  /// How far letters lean right, per unit of height.
  static const double _slant = 0.22;

  /// The tallest letter's height, in x-heights.
  static double get tallest => _l.height;

  /// A letter's advance, in x-heights.
  static const double _advance = 1.1;

  /// The gap between words, in x-heights.
  static const double _space = 1.1;

  /// Width of [words] (with their exit strokes), in x-heights.
  static double get widthInXHeights {
    var w = 0.0;
    for (final word in words) {
      w += (word.length + _tail) * _advance;
    }
    return w + (words.length - 1) * _space;
  }

  static const double _tail = 0.45;

  /// The x-height that makes [words] fit [box]: the tallest letter fills
  /// its height, and the line its width.
  static double xHeightFor(Rect box) => math.min(box.height / tallest, box.width / widthInXHeights);

  /// [words] written on [baseline] from [left], with an x-height of [x]:
  /// one stroke per word.
  static List<List<StrokePoint>> handwriting(double left, double baseline, double x) {
    final strokes = <List<StrokePoint>>[];
    var at = left;
    for (final letters in words) {
      strokes.add(word(letters, Offset(at, baseline), x));
      at += ((letters.length + _tail) * _advance + _space) * x;
    }
    return strokes;
  }

  /// One joined-up word: each letter is one cycle of an oscillation (up,
  /// over, down to the baseline) drifting right, after Hollerbach's model of
  /// cursive; then a short exit stroke rising to the right.
  static List<StrokePoint> word(List<PreviewLetter> letters, Offset origin, double x) {
    const steps = 28;
    final n = letters.length;
    final advance = _advance * x;
    final points = <StrokePoint>[];
    final total = n + _tail;
    for (var i = 0; i <= (total * steps).round(); i++) {
      final t = i / steps; // letters written so far
      final k = math.min(n - 1, t.floor());
      final cycle = t - k;
      final cur = letters[k], next = letters[math.min(n - 1, k + 1)];
      // Blend into the next letter's shape near the end of each cycle.
      final blend = _smoothstep((cycle - 0.75) / 0.25);
      final h = (cur.height + (next.height - cur.height) * blend) * x;
      final loop = cur.loop + (next.loop - cur.loop) * blend;
      final phase = 2 * math.pi * t;
      double dx, dy;
      if (t <= n) {
        dx = advance * t + loop * math.sin(phase) * advance / (2 * math.pi);
        dy = -h * 0.5 * (1 - math.cos(phase));
      } else {
        // The exit: up and away to the right, lifting off.
        final u = (t - n) / _tail;
        dx = advance * (n + (t - n) * 1.1);
        dy = -x * 0.45 * _smoothstep(u);
      }
      // Heavier going down (sin < 0 after each top), light in and out.
      final ramp = math.min(1.0, math.min(t / 0.35, (total - t) / 0.4));
      final pressure = (0.5 - 0.3 * math.sin(phase)) * (0.35 + 0.65 * ramp);
      points.add(
        StrokePoint(origin.dx + dx - dy * _slant, origin.dy + dy, pressure.clamp(0.05, 1.0)),
      );
    }
    return points;
  }

  /// A highlighter pass from [from] to [to]: a hand's slight rise and a
  /// steady pressure.
  static List<StrokePoint> highlight(Offset from, Offset to) {
    const steps = 24;
    return [
      for (var i = 0; i <= steps; i++)
        StrokePoint(
          lerpDouble(from.dx, to.dx, i / steps)!,
          lerpDouble(from.dy, to.dy, i / steps)! + math.sin(i / steps * math.pi) * -0.8,
          0.5,
        ),
    ];
  }

  static double _smoothstep(double v) {
    final t = v.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

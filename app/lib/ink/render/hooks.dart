import 'dart:math' as math;

import 'growable.dart';

/// Finds pen-down and pen-up *hooks*: the short flick a pen tip makes as it
/// lands or lifts, which would otherwise be drawn as a nub or a curl.
///
/// A hook is a short end piece (at most [maxStart] / [maxEnd] long) that
/// meets the rest of the stroke at a *kink*: the direction of the piece
/// and of the body just after it differ by more than 40°, and the turn is
/// local (more than 30° within [local] of the kink), so a stroke that
/// merely starts on a curve (radius above ~1.5 px) is left alone.
///
/// The start decision only looks at the first [decisionLength] of the
/// stroke, so it is made once, as soon as that much has been drawn, and
/// never changes as the stroke grows (the live stroke is shown only from
/// then on, see `StrokeShaper.startSettled`).
class HookFinder {
  HookFinder(double width)
    : maxStart = math.max(2.0, 1.2 * width),
      maxEnd = math.max(2.5, 1.6 * width),
      body = (0.3 * width).clamp(0.75, 2.0),
      local = (0.3 * width).clamp(0.5, 1.5);

  /// Longest hook at the start / end.
  final double maxStart, maxEnd;

  /// Length of the body after a kink that gives its direction.
  final double body;

  /// Reach of the local turn test.
  final double local;

  static final double _minTurn = 40 * math.pi / 180;
  static final double _minLocalTurn = 30 * math.pi / 180;

  /// Stroke length after which the start decision is final.
  double get decisionLength => maxStart + body;

  /// The first sample to keep of the [n] samples ([x], [y]) from [from],
  /// or null while the stroke is too short to decide and not [ended].
  int? startCut(DoubleBuffer x, DoubleBuffer y, int n, {required bool ended}) {
    final arc = <double>[0];
    for (var i = 1; i < n; i++) {
      arc.add(arc.last + _dist(x[i] - x[i - 1], y[i] - y[i - 1]));
      if (arc.last >= decisionLength) break;
    }
    if (arc.last < decisionLength && !ended) return null;
    return _cut(x, y, arc, (i) => i, maxStart);
  }

  /// How many of the [n] samples to keep once the stroke has ended (the
  /// pen-up hook removed). Only trims when the rest is at least twice as
  /// long as the hook.
  int endKeep(DoubleBuffer x, DoubleBuffer y, int n) {
    final arc = <double>[0];
    for (var i = n - 2; i >= 0; i--) {
      arc.add(arc.last + _dist(x[i + 1] - x[i], y[i + 1] - y[i]));
      if (arc.last >= maxEnd + body) break;
    }
    final cut = _cut(x, y, arc, (i) => n - 1 - i, maxEnd);
    if (cut == 0) return n;
    var total = 0.0;
    for (var i = 1; i < n; i++) {
      total += _dist(x[i] - x[i - 1], y[i] - y[i - 1]);
    }
    if (total - arc[cut] < 2 * arc[cut]) return n;
    return n - cut;
  }

  /// The furthest kink within [maxHook] of the end mapped by [at] (0 = the
  /// end sample, arc lengths in [arc]), as a count of samples to drop.
  int _cut(DoubleBuffer x, DoubleBuffer y, List<double> arc, int Function(int) at, double maxHook) {
    var cut = 0;
    final m = arc.length;
    for (var j = 1; j < m && arc[j] <= maxHook; j++) {
      var b = j + 1;
      while (b < m && arc[b] - arc[j] < body) {
        b++;
      }
      if (b >= m) break;
      var l = j - 1;
      while (l > 0 && arc[j] - arc[l] < local) {
        l--;
      }
      final jx = x[at(j)], jy = y[at(j)];
      final hx = jx - x[at(0)], hy = jy - y[at(0)];
      final bx = x[at(b)] - jx, by = y[at(b)] - jy;
      final lx = jx - x[at(l)], ly = jy - y[at(l)];
      if (_angle(hx, hy, bx, by) > _minTurn && _angle(lx, ly, bx, by) > _minLocalTurn) cut = j;
    }
    return cut;
  }

  static double _angle(double ax, double ay, double bx, double by) =>
      math.atan2(ax * by - ay * bx, ax * bx + ay * by).abs();

  static double _dist(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}

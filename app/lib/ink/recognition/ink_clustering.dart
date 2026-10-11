import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:crypto/crypto.dart';

import '../../domain/stroke.dart';

/// A word: strokes of a line close together horizontally.
class InkWord {
  const InkWord(this.strokes, this.bounds);

  /// In writing order.
  final List<Stroke> strokes;
  final Rect bounds;
}

/// A line of handwriting: strokes written side by side at the same height,
/// in writing order, and split into [words].
class InkLine {
  InkLine(this.strokes, this.bounds, this.words, {required this.letterHeight});

  /// In writing order (as recognisers expect).
  final List<Stroke> strokes;

  /// Tight bounds of the ink.
  final Rect bounds;

  /// Left to right.
  final List<InkWord> words;

  /// The typical height of the line's letters (median stroke height).
  final double letterHeight;

  /// Identifies the set of strokes (recognition results are reused while
  /// a line's strokes are unchanged).
  late final String key = InkClustering.keyOf(strokes);
}

/// Groups the strokes of a surface into lines and words, by position and
/// writing time, for handwriting recognition.
///
/// The unit of size is the typical stroke height on the surface (a median
/// of the strokes' heights, roughly a letter's height), so it works at any
/// writing size. A stroke joins a line when it overlaps the line's band
/// vertically and is at most [maxGapFactor] units away horizontally; small
/// strokes (dots, accents, crossbars, commas) only need their centre near
/// the band. Ties go to the line of the previous stroke when it was written
/// within [maxTimeGapMs]. Highlighter strokes are not writing and are left
/// out.
abstract final class InkClustering {
  static const double maxGapFactor = 3;
  static const int maxTimeGapMs = 1500;

  /// A gap between strokes wider than this many units starts a new word.
  static const double wordGapFactor = 0.6;

  /// Strokes shorter than this many units count as small (dots, accents).
  static const double smallFactor = 0.45;

  /// Lines of [strokes], top to bottom (then left to right).
  static List<InkLine> lines(Iterable<Stroke> strokes) {
    final items = [
      for (final s in strokes)
        if (!s.tool.isHighlighter) _Item(s, inkBounds(s)),
    ]..sort((a, b) => Stroke.paintOrder(a.stroke, b.stroke));
    if (items.isEmpty) return const [];
    final unit = _unit(items);
    for (final item in items) {
      item.small = item.box.height < smallFactor * unit;
    }

    final lines = <_Line>[];
    _Line? last;
    int? lastTime;
    for (final item in items) {
      _Line? best;
      var bestScore = double.negativeInfinity;
      for (final line in lines) {
        final score = _fit(line, item, unit);
        if (score == null) continue;
        final recent =
            identical(line, last) &&
            lastTime != null &&
            item.stroke.createdAt - lastTime <= maxTimeGapMs;
        final total = score + (recent ? 1 : 0);
        if (total > bestScore) {
          bestScore = total;
          best = line;
        }
      }
      (best ?? (lines..add(_Line())).last).add(item);
      last = best ?? lines.last;
      lastTime = item.stroke.createdAt;
    }
    _mergeOverlapping(lines, unit);
    lines.sort((a, b) {
      final y = a.core.top.compareTo(b.core.top);
      return y != 0 ? y : a.bounds.left.compareTo(b.bounds.left);
    });
    return [for (final line in lines) line.build(unit)];
  }

  /// Tight bounds of a stroke's ink: its points plus half its width.
  static Rect inkBounds(Stroke s) => Stroke.computeBounds(s.points, s.width / 2);

  /// A short, stable identifier of a set of strokes (order-independent).
  static String keyOf(Iterable<Stroke> strokes) {
    final ids = [for (final s in strokes) s.id]..sort();
    return sha1.convert(utf8.encode(ids.join(','))).toString().substring(0, 20);
  }

  /// The typical height of a (non-tiny) stroke: the median, at least 1.
  static double _unit(List<_Item> items) {
    final heights = [for (final i in items) i.box.height]..sort();
    final tall = heights.where((h) => h >= heights.last * 0.05).toList();
    final median = tall[tall.length ~/ 2];
    return math.max(median, 1);
  }

  /// How well [item] fits [line] (higher is better), or null if it does
  /// not belong to it.
  static double? _fit(_Line line, _Item item, double unit) {
    final band = line.core;
    final box = item.box;
    final gap = math.max(0.0, math.max(line.bounds.left - box.right, box.left - line.bounds.right));
    final maxGap = maxGapFactor * unit;
    if (gap > maxGap) return null;
    final double overlap;
    if (item.small) {
      // Dots and accents sit above the letters, commas below.
      final y = box.center.dy;
      if (y < band.top - 0.8 * unit || y > band.bottom + 0.5 * unit) return null;
      overlap = 0.5;
    } else {
      final shared = math.min(box.bottom, band.bottom) - math.max(box.top, band.top);
      final ratio = shared / math.max(1e-6, math.min(box.height, band.height));
      if (ratio < 0.5) return null;
      overlap = ratio.clamp(0, 1).toDouble();
    }
    return overlap - gap / maxGap;
  }

  /// Merges lines that ended up side by side on the same band (written in
  /// two passes, e.g. a word added later).
  static void _mergeOverlapping(List<_Line> lines, double unit) {
    var merged = true;
    while (merged) {
      merged = false;
      outer:
      for (var i = 0; i < lines.length; i++) {
        for (var j = i + 1; j < lines.length; j++) {
          final a = lines[i], b = lines[j];
          final shared = math.min(a.core.bottom, b.core.bottom) - math.max(a.core.top, b.core.top);
          final ratio = shared / math.max(1e-6, math.min(a.core.height, b.core.height));
          final gap = math.max(
            0.0,
            math.max(a.bounds.left - b.bounds.right, b.bounds.left - a.bounds.right),
          );
          if (ratio >= 0.6 && gap <= maxGapFactor * unit) {
            for (final item in b.items) {
              a.add(item);
            }
            lines.removeAt(j);
            merged = true;
            break outer;
          }
        }
      }
    }
  }
}

class _Item {
  _Item(this.stroke, this.box);

  final Stroke stroke;
  final Rect box;
  bool small = false;
}

class _Line {
  final items = <_Item>[];
  Rect bounds = Rect.zero;
  Rect? _core;

  /// The band of the line's letters (its small strokes left out).
  Rect get core => _core ?? bounds;

  void add(_Item item) {
    bounds = items.isEmpty ? item.box : bounds.expandToInclude(item.box);
    items.add(item);
    if (!item.small) _core = _core == null ? item.box : _core!.expandToInclude(item.box);
  }

  InkLine build(double unit) {
    final ordered = [...items]..sort((a, b) => Stroke.paintOrder(a.stroke, b.stroke));
    // The line's own letter height: lines may be written at other sizes.
    final heights = [
      for (final i in items)
        if (!i.small) i.box.height,
    ]..sort();
    final letter = heights.isEmpty ? unit : heights[heights.length ~/ 2];
    return InkLine(
      [for (final i in ordered) i.stroke],
      bounds,
      _words(letter),
      letterHeight: letter,
    );
  }

  List<InkWord> _words(double letter) {
    final byLeft = [...items]..sort((a, b) => a.box.left.compareTo(b.box.left));
    final gap = InkClustering.wordGapFactor * letter;
    final words = <InkWord>[];
    var current = <_Item>[];
    var box = Rect.zero;
    void flush() {
      if (current.isEmpty) return;
      current.sort((a, b) => Stroke.paintOrder(a.stroke, b.stroke));
      words.add(InkWord([for (final i in current) i.stroke], box));
      current = [];
    }

    for (final item in byLeft) {
      if (current.isNotEmpty && item.box.left > box.right + gap) flush();
      box = current.isEmpty ? item.box : box.expandToInclude(item.box);
      current.add(item);
    }
    flush();
    return words;
  }
}

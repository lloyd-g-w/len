import 'dart:convert';
import 'dart:ui';

import 'package:flutter/painting.dart' show HSVColor;
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/straighten.dart';
import 'package:len/ink/geometry/stroke_splitter.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/stroke_hit_test.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ui/color_picker/color_hex.dart';

Stroke line(
  String id, {
  double from = 0,
  double to = 100,
  InkTool tool = InkTool.ballpoint,
  StrokeStyle? style,
}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: tool,
  color: 0xFF000000,
  width: 2,
  points: [for (var x = from; x <= to; x += 10) StrokePoint(x, 0, 0.5)],
  createdAt: 7,
  style: style,
);

void main() {
  group('InkTool & StrokeStyle', () {
    test('tools parse strictly', () {
      expect(InkTool.parse('ballpoint'), InkTool.ballpoint);
      expect(InkTool.parse('highlighter'), InkTool.highlighter);
      expect(() => InkTool.parse('fountain'), throwsFormatException);
    });

    test('strokes created without a style get the defaults of their tool', () {
      expect(line('a').style, const StrokeStyle());
      expect(StrokeStyle.defaultsFor(InkTool.highlighter).opacity, 0.35);
      expect(line('a', tool: InkTool.highlighter).style.thinning, 0);
    });

    test('JSON round-trips and parses strictly', () {
      const style = StrokeStyle(opacity: 0.8, thinning: 0.7, streamline: 0.2, taperStart: 9);
      final json = jsonDecode(jsonEncode(style.toJson()));
      expect(StrokeStyle.fromJson(json), style);
      expect(StrokeStyle.fromJson({'o': 1, 'th': 0.5, 'sl': 0.4, 'future': true}).unit, 0);

      for (final bad in [
        null,
        {'o': 1, 'th': 0.5}, // missing
        {'o': 'x', 'th': 0.5, 'sl': 0.4}, // mistyped
        {'o': 1, 'th': 4, 'sl': 0.4}, // out of range
      ]) {
        expect(() => StrokeStyle.fromJson(bad), throwsFormatException, reason: '$bad');
      }
    });
  });

  group('pen options', () {
    test('styles map to outline specs', () {
      const style = StrokeStyle(thinning: 0.3, streamline: 0.4, taperStart: 5);
      final o = StrokeRenderer.specFor(InkTool.ballpoint, 3, style);
      expect(o.width, 3);
      expect(o.thinning, 0.3);
      expect(o.streamline, 0.4);
      expect(o.taperStart, 5);
      expect(o.taperEnd, 0);
      expect(o.flatCaps, isFalse);

      final h = StrokeRenderer.specFor(
        InkTool.highlighter,
        18,
        StrokeStyle.defaultsFor(InkTool.highlighter),
      );
      expect(h.flatCaps, isTrue, reason: 'highlighters have flat chisel ends');
    });

    test('taper length scales with width; off means none', () {
      final config = PenConfig.defaultsFor(InkTool.ballpoint).copyWith(taper: true);
      final style = config.styleFor(InkTool.ballpoint, 10);
      expect(style.taperStart, 10 * PenDefaults.pen.taperFactor);
      expect(config.copyWith(taper: false).styleFor(InkTool.ballpoint, 10).taperEnd, 0);
    });
  });

  group('pixel eraser', () {
    var ids = 0;
    String newId() => 'f${ids++}';

    test('cutting through the middle leaves two fragments', () {
      const tapered = StrokeStyle(taperStart: 4, taperEnd: 4);
      final s = line('a', style: tapered);
      final parts = StrokeSplitter.erase(
        s,
        const Offset(50, -10),
        const Offset(50, 10),
        5,
        newId: newId,
      )!;
      expect(parts, hasLength(2));
      expect(parts[0].points.first.x, 0);
      expect(parts[0].points.last.x, lessThanOrEqualTo(44));
      expect(parts[1].points.first.x, greaterThanOrEqualTo(56));
      expect(parts[1].points.last.x, 100);
      // Only original ends keep their taper.
      expect(parts[0].style.taperStart, 4);
      expect(parts[0].style.taperEnd, 0);
      expect(parts[1].style.taperStart, 0);
      expect(parts[1].style.taperEnd, 4);
      expect(parts.every((p) => p.createdAt == s.createdAt && p.id != s.id), isTrue);
    });

    test('misses return null, full erasure returns no fragments', () {
      final s = line('a', to: 10);
      expect(
        StrokeSplitter.erase(s, const Offset(50, 50), const Offset(60, 50), 3, newId: newId),
        isNull,
      );
      expect(
        StrokeSplitter.erase(s, const Offset(5, -1), const Offset(5, 1), 20, newId: newId),
        isEmpty,
      );
    });

    test('cuts follow the pressure-dependent ink edge, not the nominal width', () {
      // A full-pressure stroke is about twice its nominal half width.
      final heavy = Stroke(
        id: 'b',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 20,
        points: [for (var x = 0.0; x <= 200; x += 10) StrokePoint(x, 0, 1)],
        createdAt: 1,
        style: const StrokeStyle(thinning: 1),
      );
      final edge = StrokeHitTest.inkRadius(heavy, heavy.points.first);
      expect(edge, greaterThan(heavy.width / 2));
      // An eraser grazing the ink beyond the nominal half width still hits.
      final graze = Offset(100, edge + 1);
      expect(StrokeHitTest.sweepHits(heavy, graze, graze, 2), isTrue);
      final parts = StrokeSplitter.erase(heavy, graze, graze, 2, newId: newId)!;
      // The surviving ends stay clear of the eraser by their own ink radius.
      expect(parts, hasLength(2));
      expect(parts[0].points.last.x, lessThan(100));
      expect(parts[1].points.first.x, greaterThan(100));
      for (final end in [parts[0].points.last, parts[1].points.first]) {
        expect((end.offset - graze).distance, greaterThan(2 + edge));
      }
    });

    test('hairline strokes render without throwing', () {
      final hair = Stroke(
        id: 'h',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 0.1,
        points: const [StrokePoint(0, 0, 0.5)],
        createdAt: 1,
      );
      expect(StrokeRenderer.pathOf(hair).getBounds().width, greaterThan(0));
    });

    test('erasing an end trims the stroke', () {
      final parts = StrokeSplitter.erase(
        line('a'),
        const Offset(100, 0),
        const Offset(100, 0),
        10,
        newId: newId,
      )!;
      expect(parts.single.points.first.x, 0);
      expect(parts.single.points.last.x, lessThan(90));
    });

    test('a fragment cut and erased in the same drag cancels out of undo', () {
      final a = line('a');
      final f = line('f');
      final merged = InkEdit(added: [f], removed: [a]).mergedWith(InkEdit(removed: [f]));
      expect(merged.added, isEmpty);
      expect(merged.removed.map((s) => s.id), ['a']);
    });
  });

  group('straighten', () {
    test('makes an evenly sampled line between the end points', () {
      final wobbly = [
        const StrokePoint(0, 0, 0.2),
        const StrokePoint(30, 12, 0.6),
        const StrokePoint(60, -9, 0.7),
        const StrokePoint(100, 0, 0.9),
      ];
      final straight = Straighten.line(wobbly, spacing: 10);
      expect(straight.first.offset, Offset.zero);
      expect(straight.last.offset, const Offset(100, 0));
      expect(straight, hasLength(11));
      expect(straight.every((p) => p.y == 0 && p.pressure == 0.7), isTrue);
    });
  });

  group('colours', () {
    test('hex parsing and formatting', () {
      expect(ColorHex.rgb(0xFF1C7ED6), '1C7ED6');
      expect(ColorHex.parse('#1c7ed6'), 0xFF1C7ED6);
      expect(ColorHex.parse('1C7ED6', alpha: 0x80), 0x801C7ED6);
      expect(ColorHex.parse('#f80'), 0xFFFF8800);
      expect(ColorHex.parse('1C7ED680'), 0x801C7ED6);
      expect(ColorHex.parse('12345'), isNull);
      expect(ColorHex.parse('zzzzzz'), isNull);
    });

    test('HSV round-trips at 8-bit precision', () {
      for (final argb in [0xFF1C7ED6, 0x80FACC15, 0xFF000000, 0xFFFFFFFF, 0xFF7048E8]) {
        final hsv = HSVColor.fromColor(Color(argb));
        expect(hsv.toColor().toARGB32(), argb);
      }
    });
  });
}

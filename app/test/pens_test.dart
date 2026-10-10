import 'dart:convert';
import 'dart:ui';

import 'package:flutter/painting.dart' show HSVColor;
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/straighten.dart';
import 'package:len/ink/geometry/stroke_splitter.dart';
import 'package:len/ink/pen/pen_profile.dart';
import 'package:len/ink/render/nib.dart';
import 'package:len/ink/render/stroke_renderer.dart';
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
    test('unknown tools fall back to the legacy pen', () {
      expect(InkTool.parse('crayon'), InkTool.pen);
      expect(InkTool.parse('fountain'), InkTool.fountain);
    });

    test('strokes without a style render like v0.1', () {
      expect(
        StrokeStyle.defaultsFor(InkTool.pen),
        const StrokeStyle(thinning: 0.6, streamline: 0.35),
      );
      expect(StrokeStyle.defaultsFor(InkTool.highlighter).opacity, 0.35);
      expect(line('a', tool: InkTool.highlighter).style.thinning, 0);
    });

    test('JSON round-trips and parses leniently', () {
      const style = StrokeStyle(opacity: 0.8, thinning: 0.7, streamline: 0.2, taperStart: 9);
      final json = jsonDecode(jsonEncode(style.toJson()));
      expect(StrokeStyle.fromJson(json, fallback: const StrokeStyle()), style);

      const fallback = StrokeStyle(opacity: 0.5);
      final odd = StrokeStyle.fromJson({'o': 'x', 'th': 4, 'future': true}, fallback: fallback);
      expect(odd.opacity, 0.5); // mistyped → fallback
      expect(odd.thinning, 1); // out of range → clamped
      expect(StrokeStyle.fromJson(null, fallback: fallback), fallback);
    });
  });

  group('pen options', () {
    test('profiles map to perfect_freehand options', () {
      const style = StrokeStyle(thinning: 0.3, streamline: 0.4, taperStart: 5);
      final o = StrokeRenderer.optionsFor(InkTool.ballpoint, 3, style, complete: true);
      expect(o.size, 3);
      expect(o.thinning, 0.3);
      expect(o.streamline, 0.4);
      expect(o.simulatePressure, isFalse);
      expect(o.start.taperEnabled, isTrue);
      expect(o.start.customTaper, 5);
      expect(o.end.taperEnabled, isFalse);
      expect(o.end.cap, isTrue);

      final h = StrokeRenderer.optionsFor(
        InkTool.highlighter,
        18,
        StrokeStyle.defaultsFor(InkTool.highlighter),
        complete: true,
      );
      expect(h.end.cap, isFalse, reason: 'highlighters have flat chisel ends');
    });

    test('every pen type has a profile with three presets', () {
      for (final tool in [...InkTool.pens, InkTool.highlighter]) {
        final p = PenProfile.of(tool);
        expect(p.tool, tool);
        expect(p.presets, hasLength(3));
        expect(p.minWidth, lessThan(p.maxWidth));
      }
    });

    test('taper length scales with width; off means none', () {
      final config = PenConfig.defaultsFor(InkTool.brush);
      final style = config.styleFor(InkTool.brush, 10);
      expect(style.taperStart, 10 * PenProfile.of(InkTool.brush).taperFactor);
      expect(config.copyWith(taper: false).styleFor(InkTool.brush, 10).taperEnd, 0);
    });

    test('the fountain nib thins strokes running along the nib', () {
      List<StrokePoint> dir(double dx, double dy) => [
        for (var i = 0; i < 10; i++) StrokePoint(i * dx, i * dy, 0.8),
      ];
      const thinning = 0.6;
      double radius(double p) => 0.5 - thinning * (0.5 - p);
      double mid(List<StrokePoint> pts) =>
          Nib.pressures(pts, variation: 0.5, angle: PenProfile.nibAngle, thinning: thinning)[5];
      final alongNib = mid(dir(1, -1)); // up and to the right
      final acrossNib = mid(dir(1, 1)); // down and to the right
      expect(acrossNib, closeTo(0.8, 1e-9));
      expect(radius(alongNib), closeTo(radius(0.8) / 2, 1e-9));
    });
  });

  group('ToolSettings', () {
    test('customisation persists through the settings store', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final store = SettingsRepository(db);
      final a = ToolSettings(store: store)
        ..penType = InkTool.fountain
        ..setWidth(7)
        ..setColor(0x80123456)
        ..eraser = const EraserConfig(mode: EraserMode.pixel, radius: 20, highlighterOnly: true)
        ..holdToStraighten = false
        ..addFavorite(0xFFABCDEF);
      a.dispose(); // flushes the debounced save

      final b = ToolSettings(store: store);
      expect(b.penType, InkTool.fountain);
      final config = b.configOf(InkTool.fountain);
      expect(config.current, const PenPreset(color: 0xFF123456, width: 7));
      expect(config.opacity, closeTo(0x80 / 255, 1e-9));
      expect(b.eraser.mode, EraserMode.pixel);
      expect(b.eraser.highlighterOnly, isTrue);
      expect(b.holdToStraighten, isFalse);
      expect(b.favorites, [0xFFABCDEF]);
      b.dispose();
    });

    test('corrupt stored prefs fall back to defaults', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final store = SettingsRepository(db)..toolPrefs = '{"pens": {"ballpoint": {"presets": 3}}}';
      final t = ToolSettings(store: store);
      expect(
        t.configOf(InkTool.ballpoint).presets,
        PenConfig.defaultsFor(InkTool.ballpoint).presets,
      );
      store.toolPrefs = 'not json';
      expect(ToolSettings(store: store).penType, InkTool.ballpoint);
    });

    test('presets: selecting leaves the eraser; colour edits the selected one', () {
      final t = ToolSettings()..tool = EditorTool.eraser;
      t.selectPreset(2);
      expect(t.tool, EditorTool.pen);
      t.setColor(0xFFFF0000);
      expect(t.activeConfig.presets[2].color, 0xFFFF0000);
      expect(t.activeConfig.presets[0], PenConfig.defaultsFor(InkTool.ballpoint).presets[0]);
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

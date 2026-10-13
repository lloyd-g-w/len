import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/pen/recent_colors.dart';
import 'package:len/ink/tool_settings.dart';

ToolSettings restored(Object prefs) {
  final db = AppDatabase.inMemory();
  addTearDown(db.close);
  final store = SettingsRepository(db)..toolPrefs = jsonEncode(prefs);
  final tools = ToolSettings(store: store);
  addTearDown(tools.dispose);
  return tools;
}

void main() {
  group('PenConfig slots', () {
    final pen = PenConfig.defaultsFor(InkTool.ballpoint);

    test('defaults: three colours and three widths, chosen independently', () {
      expect(pen.colors, hasLength(3));
      expect(pen.widths, hasLength(3));
      final c = pen.copyWith(colorIndex: 2, widthIndex: 0);
      expect(c.color, pen.colors[2]);
      expect(c.width, pen.widths[0]);
    });

    test('slots can be added up to six and removed down to one', () {
      var c = pen;
      for (var i = 0; i < 5; i++) {
        c = c.addColor(0xFF000000 + i).addWidth(5.0 + i);
      }
      expect(c.colors, hasLength(PenConfig.maxSlots));
      expect(c.widths, hasLength(PenConfig.maxSlots));
      expect(c.colorIndex, PenConfig.maxSlots - 1, reason: 'a new slot is selected');
      for (var i = 0; i < 9; i++) {
        c = c.removeColor(0).removeWidth(c.widths.length - 1);
      }
      expect(c.colors, hasLength(1));
      expect(c.widths, hasLength(1));
      expect(c.colorIndex, 0);
      expect(c.widthIndex, 0);
    });

    test('removing a slot keeps the selection on the same value', () {
      final c = pen.copyWith(colorIndex: 2).removeColor(0);
      expect(c.color, pen.colors[2]);
      final d = pen.copyWith(widthIndex: 1).removeWidth(1);
      expect(d.width, pen.widths[0]);
    });

    test('the pen is opaque; the highlighter keeps its opacity', () {
      expect(pen.copyWith(opacity: 0.3).styleFor(InkTool.ballpoint).opacity, 1);
      final h = PenConfig.defaultsFor(InkTool.highlighter);
      expect(h.styleFor(InkTool.highlighter).opacity, h.opacity);
    });
  });

  group('ToolSettings', () {
    test('customisation persists through the settings store', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final store = SettingsRepository(db);
      final a = ToolSettings(store: store)
        ..updateConfig(InkTool.ballpoint, (c) => c.addColor(0xFF123456).withWidth(0, 7))
        ..selectWidth(0)
        ..tool = EditorTool.highlighter
        ..updateConfig(InkTool.highlighter, (c) => c.copyWith(opacity: 0.5))
        ..updateConfig(InkTool.highlighter, (c) => c.copyWith(streamline: 0.8, straight: true))
        ..eraser = const EraserConfig(mode: EraserMode.pixel, radius: 20, highlighterOnly: true)
        ..addRecentColor(0xFF00AA00);
      a.dispose(); // flushes the debounced save

      final b = ToolSettings(store: store);
      final pen = b.configOf(InkTool.ballpoint);
      expect(pen.colors.last, 0xFF123456);
      expect(pen.color, 0xFF123456);
      expect(pen.width, 7);
      final highlighter = b.configOf(InkTool.highlighter);
      expect(highlighter.opacity, 0.5);
      expect(highlighter.streamline, 0.8);
      expect(highlighter.straight, isTrue);
      expect(b.eraser.mode, EraserMode.pixel);
      expect(b.eraser.highlighterOnly, isTrue);
      expect(b.recentColors, [0xFF00AA00]);
      b.dispose();
    });

    test('corrupt stored prefs fall back to defaults', () {
      final t = restored({
        'pens': {
          'ballpoint': {'colors': 3, 'widths': 'x'},
        },
      });
      expect(t.configOf(InkTool.ballpoint), PenConfig.defaultsFor(InkTool.ballpoint));
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final store = SettingsRepository(db)..toolPrefs = 'not json';
      expect(ToolSettings(store: store).activeConfig, PenConfig.defaultsFor(InkTool.ballpoint));
    });

    test('stored configs are parsed strictly: an invalid one keeps its defaults', () {
      final valid = PenConfig.defaultsFor(InkTool.highlighter).copyWith(straight: true).toJson();
      final t = restored({
        'pens': {
          'ballpoint': {
            ...PenConfig.defaultsFor(InkTool.ballpoint).toJson(),
            'widths': [1e6],
          },
          'highlighter': valid,
        },
        'eraser': {...const EraserConfig().toJson(), 'highlighterOnly': 'yes'},
        'recent': [0x00FF0000],
      });
      expect(t.configOf(InkTool.ballpoint), PenConfig.defaultsFor(InkTool.ballpoint));
      expect(t.configOf(InkTool.highlighter).straight, isTrue);
      expect(t.eraser, const EraserConfig());
      expect(t.recentColors, isEmpty);
      t.selectColor(5); // Out of range: ignored.
      expect(t.activeConfig.colorIndex, 0);
    });

    test('PenConfig JSON requires every field, in range', () {
      const tool = InkTool.highlighter;
      final json = PenConfig.defaultsFor(tool).copyWith(straight: true, streamline: 1).toJson();
      expect(
        PenConfig.fromJson(json, tool: tool),
        PenConfig.defaultsFor(tool).copyWith(straight: true, streamline: 1),
      );
      for (final key in json.keys) {
        expect(PenConfig.fromJson({...json}..remove(key), tool: tool), isNull, reason: key);
      }
      for (final (key, bad) in [
        ('colors', <int>[]),
        ('colors', [0x7FFF0000]),
        ('widths', [1]),
        ('color', 3),
        ('opacity', 0.05),
        ('thinning', 1.5),
        ('streamline', -0.1),
        ('straight', 1),
      ]) {
        expect(PenConfig.fromJson({...json, key: bad}, tool: tool), isNull, reason: '$key $bad');
      }
    });

    test('selecting a slot leaves the eraser; widths step within range', () {
      final t = ToolSettings()..tool = EditorTool.eraser;
      t.selectColor(2);
      expect(t.tool, EditorTool.pen);
      expect(t.activeConfig.colorIndex, 2);
      t.stepWidth(5);
      expect(t.activeConfig.widthIndex, 2);
      t.stepWidth(-9);
      expect(t.activeConfig.widthIndex, 0);
      t.tool = EditorTool.highlighter;
      t.selectColor(1);
      expect(t.configOf(InkTool.highlighter).colorIndex, 1);
      expect(t.configOf(InkTool.ballpoint).colorIndex, 2);
    });
  });

  group('ToolSettings extras', () {
    test('recent colours: distinct, opaque, most recent first, at most eight', () {
      final t = ToolSettings();
      for (var i = 0; i < 10; i++) {
        t.addRecentColor(0x000000 + i);
      }
      t.addRecentColor(0x05);
      expect(t.recentColors.first, 0xFF000005);
      expect(t.recentColors, hasLength(RecentColors.max));
      expect(t.recentColors.toSet(), hasLength(RecentColors.max));
      expect(t.recentColors.take(3), [0xFF000005, 0xFF000009, 0xFF000008]);
    });

    test('previous tool: the eraser at first, then the tool used before', () {
      final t = ToolSettings();
      expect(t.previousTool, EditorTool.eraser);
      t.togglePrevious();
      expect((t.tool, t.previousTool), (EditorTool.eraser, EditorTool.pen));
      t.tool = EditorTool.highlighter;
      expect(t.previousTool, EditorTool.eraser);
    });

    test('previous tool skips the eraser when the side button erases (R7-2)', () {
      final t = ToolSettings(stylusOnly: true, penButtonErases: true);
      expect(t.previousTool, EditorTool.highlighter, reason: 'pen ↔ highlighter from the start');
      t.togglePrevious();
      expect((t.tool, t.previousTool), (EditorTool.highlighter, EditorTool.pen));
      t.tool = EditorTool.eraser;
      t.tool = EditorTool.pen;
      expect(t.previousTool, EditorTool.highlighter, reason: 'the eraser is skipped');
      t.tool = EditorTool.lasso;
      expect(t.previousTool, EditorTool.pen);
      // Fingers draw (no stylus in use) or the button selects: the eraser is back.
      t.tool = EditorTool.eraser;
      t.tool = EditorTool.pen;
      t.penButtonErases = false;
      expect(t.previousTool, EditorTool.eraser);
      t.penButtonErases = true;
      t.stylusOnly = false;
      expect(t.previousTool, EditorTool.eraser);
    });

    test('Reset restores the feel settings and keeps the slots', () {
      final h = PenConfig.defaultsFor(InkTool.highlighter);
      final custom = h.addColor(0xFF123456).copyWith(opacity: 0.8, streamline: 1, straight: true);
      final reset = custom.withFeelDefaults(InkTool.highlighter);
      expect(reset.colors, custom.colors);
      expect(reset, h.addColor(0xFF123456));
    });

    test('straight strokes need no stabiliser', () {
      final h = PenConfig.defaultsFor(InkTool.highlighter);
      expect(h.styleFor(InkTool.highlighter).streamline, h.streamline);
      expect(h.copyWith(straight: true).styleFor(InkTool.highlighter).streamline, 0);
    });
  });
}

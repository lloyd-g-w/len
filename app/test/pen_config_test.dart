import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/tool_settings.dart';

ToolSettings restored(Object prefs, {List<int>? favorites}) {
  final db = AppDatabase.inMemory();
  addTearDown(db.close);
  final store = SettingsRepository(db)..toolPrefs = jsonEncode(prefs);
  if (favorites != null) store.favoriteColors = favorites;
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
      expect(pen.copyWith(opacity: 0.3).styleFor(InkTool.ballpoint, 2).opacity, 1);
      final h = PenConfig.defaultsFor(InkTool.highlighter);
      expect(h.styleFor(InkTool.highlighter, 10).opacity, h.opacity);
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
        ..eraser = const EraserConfig(mode: EraserMode.pixel, radius: 20, highlighterOnly: true)
        ..holdToStraighten = false
        ..addFavorite(0xFFABCDEF);
      a.dispose(); // flushes the debounced save

      final b = ToolSettings(store: store);
      final pen = b.configOf(InkTool.ballpoint);
      expect(pen.colors.last, 0xFF123456);
      expect(pen.color, 0xFF123456);
      expect(pen.width, 7);
      expect(b.configOf(InkTool.highlighter).opacity, 0.5);
      expect(b.eraser.mode, EraserMode.pixel);
      expect(b.eraser.highlighterOnly, isTrue);
      expect(b.holdToStraighten, isFalse);
      expect(b.favorites, [0xFFABCDEF]);
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

    test('out-of-range values are clamped; favourites deduplicated', () {
      final t = restored(
        {
          'pens': {
            'ballpoint': {
              'colors': [0x00FF0000, 'x', 0xFF00FF00],
              'widths': [1e6, 0.001, -1],
              'color': 9,
              'width': 1,
            },
            'highlighter': {'opacity': 0},
          },
        },
        favorites: [1, 2, 1, for (var i = 0; i < 40; i++) 100 + i],
      );
      final pen = t.configOf(InkTool.ballpoint);
      expect(pen.colors, [0xFFFF0000, 0xFF00FF00]);
      expect(pen.widths, [PenDefaults.pen.maxWidth, PenDefaults.pen.minWidth]);
      expect(pen.colorIndex, 0);
      expect(pen.width, PenDefaults.pen.minWidth);
      expect(t.configOf(InkTool.highlighter).opacity, PenConfig.minOpacity);
      expect(t.favorites.take(3), [1, 2, 100]);
      expect(t.favorites, hasLength(ToolSettings.maxFavorites));
      t.selectColor(5); // Out of range: ignored.
      expect(t.activeConfig.colorIndex, 0);
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
}

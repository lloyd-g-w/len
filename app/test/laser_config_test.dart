import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/tool_settings.dart';

/// The laser's quick colour and size slots: editing, counts, Reset's
/// defaults, keyboard selection and persistence.
void main() {
  group('LaserConfig slots', () {
    test('three colours (red, green, blue) and three sizes by default, the middle size', () {
      const c = LaserConfig();
      expect(c.colors, [0xFFFF2D2D, 0xFF2BD957, 0xFF2F8BFF]);
      expect(c.sizes, hasLength(3));
      expect(c.color, 0xFFFF2D2D);
      expect(c.size, 6);
    });

    test('slots change one at a time; colours made opaque, sizes clamped', () {
      final c = const LaserConfig().withColor(1, 0x00123456).withSize(2, 40);
      expect(c.colors[1], 0xFF123456);
      expect(c.sizes[2], LaserConfig.maxSize);
      expect(c.colors[0], LaserConfig.defaultColors[0]);
      expect(c.withSize(0, 1).sizes[0], LaserConfig.minSize);
    });

    test('1 to 5 slots per row; a new slot is selected; removal keeps a valid selection', () {
      var c = const LaserConfig();
      c = c.addColor(0xFFFF8A00).addColor(0xFFFFD60A);
      expect(c.colors, hasLength(5));
      expect(c.colorIndex, 4);
      expect(c.addColor(0xFFE83CFF), c, reason: 'full');
      c = c.removeColor(4).removeColor(3).removeColor(2).removeColor(1);
      expect(c.colors, [LaserConfig.defaultColors[0]]);
      expect(c.colorIndex, 0);
      expect(c.removeColor(0), c, reason: 'the last slot stays');
      c = c.addSize(12);
      expect(c.sizes, [4, 6, 10, 12]);
      expect(c.sizeIndex, 3);
      c = c.removeSize(0);
      expect(c.sizes, [6, 10, 12]);
      expect(c.sizeIndex, 2, reason: 'still the same slot');
    });

    test('feel defaults keep the slots', () {
      final custom = const LaserConfig(
        mode: LaserMode.dot,
        fade: LaserFade.pause,
        duration: Duration(milliseconds: 2500),
        hold: Duration(milliseconds: 4000),
      ).withColor(0, 0xFF000000).addSize(14);
      final reset = custom.withFeelDefaults();
      expect(reset.colors, custom.colors);
      expect(reset.sizes, custom.sizes);
      expect(reset.sizeIndex, custom.sizeIndex);
      expect(reset.mode, LaserMode.trail);
      expect(reset.fade, LaserFade.stroke);
      expect(reset.duration, LaserConfig.defaultDuration);
      expect(reset.hold, LaserConfig.defaultHold);
    });
  });

  group('LaserConfig JSON', () {
    test('round trip', () {
      const c = LaserConfig(
        mode: LaserMode.dot,
        colors: [0xFF000000, 0xFFFFFFFF],
        colorIndex: 1,
        sizes: [3, 16, 5, 7, 9],
        sizeIndex: 4,
        duration: Duration(milliseconds: 2000),
        fade: LaserFade.pause,
        hold: Duration(milliseconds: 3000),
      );
      expect(LaserConfig.fromJson(c.toJson()), c);
    });

    test('a malformed row takes its defaults with its selection; the rest is kept', () {
      Map<String, Object?> patched(Map<String, Object?> patch) => {
        ...const LaserConfig(mode: LaserMode.dot, colorIndex: 2, sizeIndex: 0).toJson(),
        ...patch,
      };
      for (final patch in <Map<String, Object?>>[
        {'colors': <int>[]},
        {'colors': List.filled(6, 0xFF000000)},
        {
          'colors': [0x00FF0000],
        },
        {'colors': 'red'},
        {'color': 3},
        {'color': null},
      ]) {
        final c = LaserConfig.fromJson(patched(patch));
        expect(c.colors, LaserConfig.defaultColors, reason: '$patch');
        expect(c.colorIndex, 0, reason: '$patch');
        expect(c.sizeIndex, 0, reason: 'sizes kept: $patch');
        expect(c.mode, LaserMode.dot);
      }
      for (final patch in <Map<String, Object?>>[
        {
          'sizes': [2],
        },
        {
          'sizes': [20],
        },
        {'sizes': <double>[]},
        {'size': -1},
        {'size': 1.5},
      ]) {
        final c = LaserConfig.fromJson(patched(patch));
        expect(c.sizes, LaserConfig.defaultSizes, reason: '$patch');
        expect(c.sizeIndex, LaserConfig.defaultSizeIndex, reason: '$patch');
        expect(c.colorIndex, 2, reason: 'colours kept: $patch');
      }
      expect(LaserConfig.fromJson(null), const LaserConfig());
      expect(LaserConfig.fromJson('x'), const LaserConfig());
    });
  });

  group('ToolSettings and the laser', () {
    test('while the laser is the tool, 1–5 pick its colours and [ ] its sizes', () {
      final tools = ToolSettings()..tool = EditorTool.laser;
      addTearDown(tools.dispose);
      tools.selectColor(2);
      expect(tools.laser.colorIndex, 2);
      expect(tools.tool, EditorTool.laser, reason: 'the laser stays in hand');
      expect(tools.configOf(InkTool.ballpoint).colorIndex, 0);
      tools.selectColor(3);
      expect(tools.laser.colorIndex, 2, reason: 'no fourth slot');
      tools.stepWidth(1);
      expect(tools.laser.sizeIndex, 2);
      tools.stepWidth(1);
      expect(tools.laser.sizeIndex, 2, reason: 'clamped');
      tools.stepWidth(-5);
      expect(tools.laser.sizeIndex, 0);
      tools.selectWidth(1);
      expect(tools.laser.sizeIndex, 1);
    });

    test('the laser slots persist with the tool settings', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final store = SettingsRepository(db);
      final config = const LaserConfig()
          .withColor(0, 0xFF101010)
          .addColor(0xFFE83CFF)
          .addSize(14)
          .removeSize(0);
      final tools = ToolSettings(store: store)..laser = config;
      tools.dispose();
      final restored = ToolSettings(store: store);
      addTearDown(restored.dispose);
      expect(restored.laser, config);
      expect(restored.laser.colors, [0xFF101010, 0xFF2BD957, 0xFF2F8BFF, 0xFFE83CFF]);
      expect(restored.laser.sizes, [6, 10, 14]);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/tools/laser_options_panel.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

/// The laser trail's feel like the pen's (pressure sensitivity, stabiliser,
/// ends): defaults, Reset, persistence (old settings still load) and the
/// options panel. How the trail draws with them: laser_trail_shape_test.
void main() {
  const feel = LaserConfig(
    thinning: 0.6,
    streamline: 0.4,
    ends: PenEnds(style: StrokeEnds.tapered, taperLength: 6, taperAt: TaperAt.end),
  );

  group('LaserConfig feel', () {
    test('defaults are the trail as it always was: one width, no stabiliser, flat ends', () {
      const c = LaserConfig();
      expect(c.thinning, 0);
      expect(c.streamline, 0);
      expect(c.ends.style, StrokeEnds.flat);
      expect(LaserConfig.endStyles, [StrokeEnds.round, StrokeEnds.tapered, StrokeEnds.flat]);
    });

    test('Reset (feel defaults) puts them back, keeping the slots', () {
      final custom = feel.withColor(0, 0xFF000000).addSize(14);
      final reset = custom.withFeelDefaults();
      expect(reset.thinning, 0);
      expect(reset.streamline, 0);
      expect(reset.ends, LaserConfig.defaultEnds);
      expect(reset.colors, custom.colors);
      expect(reset.sizes, custom.sizes);
      expect(feel.withFeelDefaults(), const LaserConfig());
    });

    test('JSON round trip', () {
      expect(LaserConfig.fromJson(feel.toJson()), feel);
      final round = feel.copyWith(ends: const PenEnds());
      expect(LaserConfig.fromJson(round.toJson()), round);
    });

    test('settings saved before the feel load with the defaults; malformed ones too', () {
      final old = const LaserConfig(mode: LaserMode.dot, colorIndex: 2).toJson()
        ..remove('thinning')
        ..remove('streamline')
        ..remove('ends');
      final c = LaserConfig.fromJson(old);
      expect(c, const LaserConfig(mode: LaserMode.dot, colorIndex: 2));
      for (final patch in <Map<String, Object?>>[
        {'thinning': 2, 'streamline': -1},
        {'thinning': 'high', 'streamline': null},
        {
          'ends': {'style': 'pointy', 'taper': 4, 'at': 'both'},
        },
        {
          'ends': {'style': 'tapered', 'taper': 40, 'at': 'both'},
        },
        {'ends': 'round'},
      ]) {
        final c = LaserConfig.fromJson({...feel.toJson(), ...patch});
        for (final key in patch.keys) {
          final v = switch (key) {
            'thinning' => c.thinning,
            'streamline' => c.streamline,
            _ => c.ends,
          };
          expect(v, key == 'ends' ? LaserConfig.defaultEnds : 0, reason: '$patch');
        }
        expect(c.colors, feel.colors, reason: 'the rest kept: $patch');
      }
    });

    test('persist with the tool settings', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final store = SettingsRepository(db);
      ToolSettings(store: store)
        ..laser = feel
        ..dispose();
      final restored = ToolSettings(store: store);
      addTearDown(restored.dispose);
      expect(restored.laser, feel);
    });
  });

  group('laser options panel', () {
    Future<ToolSettings> pumpPanel(WidgetTester tester, [LaserConfig? laser]) async {
      final tools = ToolSettings()..laser = laser ?? const LaserConfig();
      addTearDown(tools.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Material(
            child: SingleChildScrollView(
              child: SizedBox(width: 320, child: LaserOptionsPanel(tools: tools)),
            ),
          ),
        ),
      );
      return tools;
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    testWidgets('the feel is not offered (one flat panel); Reset puts it back', (tester) async {
      final tools = await pumpPanel(tester, feel);
      for (final hidden in ['Feel', 'Pressure sensitivity', 'Stabiliser', 'Ends']) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
      expect(find.text('Fade'), findsOneWidget);
      expect(tools.laser.ends, feel.ends, reason: 'the stored feel keeps working');
      await tapText(tester, 'Dot');
      expect(find.text('Fade'), findsNothing, reason: 'the dot does not fade');
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(tools.laser, const LaserConfig());
    });
  });
}

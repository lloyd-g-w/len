import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/app_preferences.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/pen/slot_counts.dart';
import 'package:len/features/settings/toolbar_settings.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

/// How many quick colours and sizes each tool shows: set in Settings →
/// Toolbar, mirrored into the editor's tools.
void main() {
  late AppDatabase db;
  late AppPreferences prefs;

  setUp(() {
    db = AppDatabase.inMemory();
    prefs = AppPreferences(SettingsRepository(db));
  });
  tearDown(() => db.close());

  test('three and three by default; stored per tool; invalid values read as the default', () {
    for (final tool in SlotTool.values) {
      expect(prefs.slotCounts(tool), SlotCounts.defaults);
    }
    prefs.setSlotCounts(SlotTool.highlighter, const SlotCounts(5, 1));
    expect(prefs.slotCounts(SlotTool.highlighter), const SlotCounts(5, 1));
    expect(prefs.slotCounts(SlotTool.pen), SlotCounts.defaults);
    expect(SlotCounts.parse('0,3'), SlotCounts.defaults);
    expect(SlotCounts.parse('6,3'), SlotCounts.defaults);
    expect(SlotCounts.parse('x'), SlotCounts.defaults);
    expect(SlotCounts.defaults.copyWith(colors: 9), const SlotCounts(5, 3), reason: 'clamped');
  });

  test('the editor\'s tools follow the counts: new slots differ, the selection stays', () {
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    tools.updateConfig(InkTool.ballpoint, (c) => c.copyWith(colorIndex: 1));
    final before = tools.configOf(InkTool.ballpoint);
    prefs
      ..setSlotCounts(SlotTool.pen, const SlotCounts(5, 1))
      ..setSlotCounts(SlotTool.laser, const SlotCounts(1, 5));
    applySlotCounts(tools, prefs);
    final pen = tools.configOf(InkTool.ballpoint);
    expect(pen.colors, hasLength(5));
    expect(pen.colors.toSet(), hasLength(5), reason: 'new colours differ');
    expect(pen.colors.take(3), before.colors, reason: 'the old ones kept');
    expect(pen.colorIndex, 1);
    expect(pen.widths, [before.widths.first]);
    expect(pen.widthIndex, 0, reason: 'the last one left');
    expect(tools.configOf(InkTool.highlighter), PenConfig.defaultsFor(InkTool.highlighter));
    expect(tools.laser.colors, hasLength(1));
    expect(tools.laser.sizes, hasLength(5));
    expect(tools.laser.sizes.toSet(), hasLength(5), reason: 'new sizes differ');

    // Already there: nothing changes, nothing notifies.
    var notified = false;
    tools.addListener(() => notified = true);
    applySlotCounts(tools, prefs);
    expect(notified, isFalse);
  });

  testWidgets('Settings → Toolbar steps each tool\'s colours and sizes (1 to 5)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: ToolbarSettings(preferences: prefs)),
        ),
      ),
    );
    for (final tool in SlotTool.values) {
      expect(find.text(tool.label), findsOneWidget);
    }
    await tester.tap(find.byTooltip('More highlighter colours'));
    await tester.pump();
    expect(prefs.slotCounts(SlotTool.highlighter), const SlotCounts(4, 3));
    final row = find.byKey(const ValueKey('slot-counts-highlighter'));
    expect(find.descendant(of: row, matching: find.text('4')), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Fewer laser pointer sizes'));
      await tester.pump();
    }
    expect(prefs.slotCounts(SlotTool.laser), const SlotCounts(3, 1));
    final fewer = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Fewer laser pointer sizes'),
        matching: find.byType(IconButton),
      ),
    );
    expect(fewer.onPressed, isNull, reason: 'one at least');
    expect(prefs.slotCounts(SlotTool.pen), SlotCounts.defaults);
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/toolbar/toolbar_config.dart';
import 'package:len/features/editor/toolbar/toolbar_editor.dart';
import 'package:len/ink/tool_settings.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

const blue = FavouritePen(tool: EditorTool.pen, color: 0xFF1C4ED8, width: 2.5);
const yellow = FavouritePen(tool: EditorTool.highlighter, color: 0xFFFACC15, width: 16);

void main() {
  group('ToolbarConfig', () {
    test('arranges tools in the user order without hidden ones, keeping the active', () {
      final config = const ToolbarConfig()
          .moveBefore(EditorTool.lasso, EditorTool.pen)
          .toggle(EditorTool.laser)
          .toggle(EditorTool.shape);
      final tools = [EditorTool.pen, EditorTool.highlighter, EditorTool.lasso, EditorTool.laser];
      expect(config.arrange(tools, (t) => t), [
        EditorTool.lasso,
        EditorTool.pen,
        EditorTool.highlighter,
      ]);
      expect(config.arrange(tools, (t) => t, keep: EditorTool.laser), hasLength(4));
    });

    test('reorders as a reorderable list reports it, among the shown tools', () {
      const shown = [EditorTool.pen, EditorTool.highlighter, EditorTool.eraser];
      // Pen to the end of the shown tools.
      var config = const ToolbarConfig().reorder(shown, 0, 2);
      expect(
        config.order.indexOf(EditorTool.pen),
        greaterThan(config.order.indexOf(EditorTool.eraser)),
      );
      // And back to the front.
      config = config.reorder([EditorTool.highlighter, EditorTool.eraser, EditorTool.pen], 2, 0);
      expect(config.order.first, EditorTool.pen);
    });

    test('at least one tool stays visible', () {
      var config = const ToolbarConfig();
      for (final t in EditorTool.values) {
        config = config.toggle(t);
      }
      final visible = EditorTool.values.where(
        (t) => !config.hidden.contains(t) && t != EditorTool.selectText,
      );
      expect(visible, hasLength(1));
    });

    test('favourites: unique, capped, removable; round-trips through JSON', () {
      var config = const ToolbarConfig().addFavourite(blue).addFavourite(blue).addFavourite(yellow);
      expect(config.favourites, [blue, yellow]);
      for (var i = 0; i < 20; i++) {
        config = config.addFavourite(FavouritePen(tool: EditorTool.pen, color: i, width: 1));
      }
      expect(config.favourites, hasLength(ToolbarConfig.maxFavourites));
      config = config.removeFavourite(0).toggle(EditorTool.text);
      final back = ToolbarConfig.decode(config.encode());
      expect(back, config);
      expect(back.favourites.first, yellow);
      expect(back.hidden, {EditorTool.text});
      // Malformed or missing: the default toolbar.
      expect(ToolbarConfig.decode('nonsense'), const ToolbarConfig());
      expect(ToolbarConfig.decode(null).isDefault, isTrue);
      // A tool missing from a stored order is appended.
      final partial = ToolbarConfig.decode(
        '{"order":["laser","pen"],"favourites":[{"tool":"eraser"}]}',
      );
      expect(partial.order.take(2), [EditorTool.laser, EditorTool.pen]);
      expect(partial.order.toSet(), EditorTool.values.toSet());
      expect(partial.favourites, isEmpty);
    });
  });

  test('a favourite selects matching slots, or loads into the selected ones', () {
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    tools.tool = EditorTool.lasso;
    final pen = tools.configOf(InkTool.ballpoint);
    // Colour 1 and width 1 of the defaults.
    FavouritePen(tool: EditorTool.pen, color: pen.colors[1], width: pen.widths[2]).applyTo(tools);
    expect(tools.tool, EditorTool.pen);
    expect(tools.activeConfig.colorIndex, 1);
    expect(tools.activeConfig.widthIndex, 2);
    expect(tools.activeConfig.colors, pen.colors); // Nothing replaced.
    // Not among the quick slots: replaces the selected ones.
    yellow.applyTo(tools);
    expect(tools.tool, EditorTool.highlighter);
    expect(yellow.isActiveIn(tools), isTrue);
    const odd = FavouritePen(tool: EditorTool.pen, color: 0xFF123456, width: 7);
    odd.applyTo(tools);
    final now = tools.configOf(InkTool.ballpoint);
    expect(now.colors, hasLength(pen.colors.length));
    expect(now.color, 0xFF123456);
    expect(now.width, 7);
    expect(FavouritePen.current(tools), odd);
  });

  testWidgets('customise the toolbar: hide, favourites, persisted, reset', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toolbar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customise toolbar…'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolbarEditor), findsOneWidget);
    expect(find.byType(EditorToolbar), findsNothing);

    // Hide the laser pointer.
    await tester.tap(find.byTooltip('Hide Laser pointer'));
    await tester.pumpAndSettle();
    expect(s.preferences.toolbarConfig.hidden, {EditorTool.laser});
    // Pin the pen in use.
    await tester.tap(find.byKey(const ValueKey('add-favourite')));
    await tester.pumpAndSettle();
    expect(s.preferences.toolbarConfig.favourites, hasLength(1));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(EditorToolbar), findsOneWidget);
    expect(find.byTooltip('Laser pointer (K)'), findsNothing);
    expect(find.byKey(const ValueKey('favourite-0')), findsOneWidget);
    // The favourite draws with what was pinned after other changes.
    final pinned = s.preferences.toolbarConfig.favourites.single;
    await tester.tap(find.byTooltip('Highlighter (H)'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favourite-0')));
    await tester.pump();
    expect(tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools.tool, EditorTool.pen);
    expect(
      pinned.isActiveIn(tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools),
      isTrue,
    );
    // The shortcut still reaches the hidden tool, shown while active.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(find.byTooltip('Laser pointer (K)'), findsOneWidget);

    // Reset.
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toolbar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customise toolbar…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(s.preferences.toolbarLayout, isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('customise the toolbar: a mouse drags at once, touch needs a hold', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toolbar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customise toolbar…'));
    await tester.pumpAndSettle();
    final first = EditorTool.values.first;
    final tile = find.byKey(ValueKey('edit-${first.name}'));

    Future<void> drag(PointerDeviceKind kind) async {
      final from = tester.getCenter(tile);
      final gesture = await tester.startGesture(from, kind: kind);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(from + Offset(i * 16.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // A quick touch drag doesn't reorder (it would scroll).
    await drag(PointerDeviceKind.touch);
    expect(s.preferences.toolbarConfig.order.first, first);
    // A mouse drag reorders without a long press.
    await drag(PointerDeviceKind.mouse);
    expect(s.preferences.toolbarConfig.order.first, isNot(first));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('phones: favourites in the tool switcher', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(390, 844));
    s.preferences.toolbarConfig = const ToolbarConfig().addFavourite(yellow);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('Switch tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favourite-0')).last);
    await tester.pumpAndSettle();
    final tools = tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools;
    expect(tools.tool, EditorTool.highlighter);
    expect(yellow.isActiveIn(tools), isTrue);
    await closeEditor(tester);
  });
}

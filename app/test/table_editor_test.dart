import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/features/editor/tools/text/table_editor_layer.dart';
import 'package:len/features/editor/tools/text_box_editor.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;
import 'text_box_ui_test.dart' show ctrl, mockClipboardText, paste;

/// An editor on a surface holding box `t` ([data], 300 wide), opened.
Future<(SurfaceModel, TextEditSession)> openBox(WidgetTester tester, TextData data) async {
  await tester.binding.setSurfaceSize(const Size(1000, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final db = AppDatabase.inMemory();
  addTearDown(db.close);
  final clock = FakeClock();
  final model = SurfaceModel(
    surfaceId: 's',
    repository: StrokeRepository(db, deviceId: 'd', clock: clock),
    elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
    clock: clock,
  );
  addTearDown(model.dispose);
  final session = TextEditSession(model: model, clock: clock);
  addTearDown(session.dispose);
  final box = textBox('t', const Offset(80, 120), text: '');
  model.commit(
    InkEdit(
      addedElements: [
        box.copyWith(
          rect: Rect.fromLTWH(80, 120, 300, 40),
          data: data.copyWith(autoWidth: false).toJson(),
        ),
      ],
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: TextBoxEditor(
          session: session,
          viewport: ViewportController()..setSize(const Size(1000, 700)),
          tools: ToolSettings(stylusOnly: false),
        ),
      ),
    ),
  );
  session.edit(model.elementById('t')!);
  await tester.pumpAndSettle();
  return (model, session);
}

RichTextController boxController(WidgetTester tester) =>
    tester.widget<TableEditorLayer>(find.byType(TableEditorLayer)).box;

Finder get cellField =>
    find.descendant(of: find.byType(TableEditorLayer), matching: find.byType(TextField));

/// Types [text] into the cell edited (its whole text).
Future<void> typeInCell(WidgetTester tester, String text) async {
  await tester.enterText(cellField, text);
  await tester.pump();
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

List<String> cells(TextData data) {
  final t = TextTables.of(data.paras).single;
  final lines = data.text.split('\n');
  return [for (var l = t.line; l < t.end; l++) lines[l]];
}

void main() {
  testWidgets('insert a table from the format bar, type in cells, Tab / Enter, undo, store', (
    tester,
  ) async {
    final (model, session) = await openBox(tester, const TextData());
    await tester.tap(find.byTooltip('Insert table'));
    await tester.pumpAndSettle();
    // Pick 2 rows × 3 columns on the grid (26-px cells with a pointer).
    final grid = find.byKey(const ValueKey('table-picker-grid'));
    await tester.tapAt(tester.getTopLeft(grid) + const Offset(26 * 2.5, 26 * 1.5));
    await tester.pumpAndSettle();
    final box = boxController(tester);
    expect(TextTables.of(box.data.paras).single.columns, 3);
    expect(box.activeCell, 0);
    expect(cellField, findsOneWidget);

    await typeInCell(tester, '- ');
    expect(cells(box.data).first, '- ', reason: 'no list in a cell');
    await typeInCell(tester, 'a');
    await press(tester, LogicalKeyboardKey.tab);
    expect(box.activeCell, 1);
    await typeInCell(tester, 'b');
    await press(tester, LogicalKeyboardKey.enter);
    expect(box.activeCell, 4, reason: 'Enter: the cell below');
    await typeInCell(tester, 'e');
    await press(tester, LogicalKeyboardKey.tab, shift: true);
    expect(box.activeCell, 3);
    // Tab from the last cell adds a row.
    box.enterCell(5);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.tab);
    expect(TextTables.of(box.data.paras).single.rows, 3);
    expect(box.activeCell, 6);
    expect(cells(box.data), ['a', 'b', '', '', 'e', '', '', '', '']);

    // Undo: the row, then the typing.
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(TextTables.of(box.data.paras).single.rows, 2);
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(cells(box.data), ['a', 'b', '', '', '', '']);
    expect(box.activeCell, 4, reason: 'back in the cell undone');

    session.end();
    await tester.pumpAndSettle();
    final stored = TextData.fromJson(model.elementById('t')!.data);
    expect(cells(stored), ['a', 'b', '', '', '', '']);
  });

  testWidgets('arrows cross cell borders and leave the table', (tester) async {
    final b = RichTextBuffer(const TextData(text: 'top\nend'));
    final t = b.insertTable(4, 2, 2);
    for (final (k, s) in ['ab', 'cd', 'ef', 'gh'].indexed) {
      b.setCell(t.line + k, s, List.filled(2, SpanStyle.plain));
    }
    await openBox(tester, b.toData(const TextData()));
    final box = boxController(tester);
    box.enterCell(1, atEnd: true);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(box.activeCell, 2, reason: 'right at the end: the next cell');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(box.activeCell, 4);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(box.activeCell, isNull, reason: 'down from the last row leaves the table');
    expect(box.modelSelection.start, box.data.text.indexOf('end'));
    // Up from the line after the table goes into its last row.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(box.activeCell, isNotNull);
    expect(TextTables.of(box.data.paras).single.cellOf(box.activeCell!).row, 1);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(box.activeCell, isNull);
    expect(box.modelSelection.start, lessThanOrEqualTo(3));
  });

  testWidgets('a block of cells: Shift+arrow selects, copy as table, delete clears', (
    tester,
  ) async {
    final b = RichTextBuffer(const TextData());
    final t = b.insertTable(0, 2, 2);
    for (final (k, s) in ['ab', 'cd', 'ef', 'gh'].indexed) {
      b.setCell(t.line + k, s, List.filled(2, SpanStyle.plain));
    }
    String? clip;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null),
    );
    await openBox(tester, b.toData(const TextData()));
    final box = boxController(tester);
    box.enterCell(0, atEnd: true);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight, shift: true);
    expect(box.cellRange, isNotNull);
    await press(tester, LogicalKeyboardKey.arrowDown, shift: true);
    expect(box.cellRange!.bottom, 1);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(clip, 'ab\tcd\nef\tgh');
    await press(tester, LogicalKeyboardKey.delete);
    expect(cells(box.data), ['', '', '', '']);
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(cells(box.data), ['ab', 'cd', 'ef', 'gh']);
  });

  testWidgets('Ctrl+V with a block of cells selected pastes from its top left cell on', (
    tester,
  ) async {
    final b = RichTextBuffer(const TextData());
    final t = b.insertTable(0, 2, 2);
    for (final (k, s) in ['ab', 'cd', 'ef', 'gh'].indexed) {
      b.setCell(t.line + k, s, List.filled(2, SpanStyle.plain));
    }
    await openBox(tester, b.toData(const TextData()));
    final box = boxController(tester);
    Future<void> selectSecondRow() async {
      box.enterCell(2, atEnd: true);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(box.cellRange, isNotNull);
    }

    mockClipboardText('1\t2');
    await selectSecondRow();
    await paste(tester);
    await tester.pumpAndSettle();
    expect(cells(box.data), ['ab', 'cd', '1', '2']);
    // One value replaces the top left cell.
    mockClipboardText('z');
    await selectSecondRow();
    await paste(tester);
    await tester.pumpAndSettle();
    expect(cells(box.data), ['ab', 'cd', 'z', '2']);
    expect(box.activeCell, 2);
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(cells(box.data), ['ab', 'cd', '1', '2'], reason: 'one undo step');
  });

  testWidgets('rows of tab-separated text pasted into a cell fill cells, adding rows and columns', (
    tester,
  ) async {
    mockClipboardText('1\t2\t3\n4\t5\t6\n');
    final b = RichTextBuffer(const TextData());
    b.insertTable(0, 1, 2);
    await openBox(tester, b.toData(const TextData()));
    final box = boxController(tester);
    box.enterCell(0);
    await tester.pumpAndSettle();
    await paste(tester);
    await tester.pumpAndSettle();
    expect(cells(box.data), ['1', '2', '3', '4', '5', '6'], reason: 'a third column added');
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(cells(box.data), ['', '']);
  });

  testWidgets('dragging a column border resizes it, one undo step', (tester) async {
    final b = RichTextBuffer(const TextData());
    b.insertTable(0, 1, 2);
    await openBox(tester, b.toData(const TextData()));
    final box = boxController(tester);
    final border = find.byKey(const ValueKey('table-border-0-0-0'));
    expect(border, findsOneWidget);
    await tester.drag(border, const Offset(60, 0));
    await tester.pumpAndSettle();
    final widths = TextTables.of(box.data.paras).single.spec.widths;
    expect(widths.first, greaterThan(0.6));
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(TextTables.of(box.data.paras).single.spec.widths.first, closeTo(0.5, 0.001));
  });

  testWidgets('tapping a cell edits it; the table menu adds and removes', (tester) async {
    final b = RichTextBuffer(const TextData(text: 'x'));
    b.insertTable(1, 2, 2);
    await openBox(tester, b.toData(const TextData()));
    final box = boxController(tester);
    // The second row's second cell (rows start below the first line).
    final layer = tester.getTopLeft(find.byType(TableEditorLayer));
    final rows = TextBoxLayout.planned(box.data, box.wrapWidth, box.plan).rows;
    final r = rows[1].rect;
    await tester.tapAt(layer + Offset(r.left + r.width * 0.75, r.center.dy));
    await tester.pumpAndSettle();
    expect(box.activeCell, 4);
    await tester.tap(find.byTooltip('Table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert column right'));
    await tester.pumpAndSettle();
    expect(TextTables.of(box.data.paras).single.columns, 3);
    await tester.tap(find.byTooltip('Table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Header row'));
    await tester.pumpAndSettle();
    expect(TextTables.of(box.data.paras).single.spec.header, isTrue);
    await tester.tap(find.byTooltip('Table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete table'));
    await tester.pumpAndSettle();
    expect(TextTables.of(box.data.paras), isEmpty);
    expect(box.activeCell, isNull);
  });

  testWidgets('a table being edited (golden): the cell field over the painted cells', (
    tester,
  ) async {
    final b = RichTextBuffer(const TextData(text: 'Plan'));
    final t = b.insertTable(4, 3, 3, header: true);
    final words = [
      'Day',
      'Task',
      'Done',
      'Mon',
      'Write the long report draft',
      'yes',
      'Tue',
      '',
      'no',
    ];
    for (final (k, s) in words.indexed) {
      b.setCell(t.line + k, s, List.filled(s.length, SpanStyle.plain));
    }
    await openBox(tester, b.toData(const TextData(fontSize: 20)));
    final box = boxController(tester);
    box.enterCell(t.line + 4, atEnd: true);
    await tester.pumpAndSettle();
    box.selectCells(null);
    box.enterCell(t.line + 4, atEnd: true);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/table_editing.png'));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/tools/text/table_editor_layer.dart';
import 'package:len/features/editor/tools/text_options_panel.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show text;
import 'content_tools_ui_test.dart';

/// Whether the text [finder] shows is drawn whole: on one line where
/// [oneLine], and not cut by its box.
void _whole(WidgetTester tester, Finder finder, {bool oneLine = false}) {
  final p = tester.renderObject<RenderParagraph>(finder);
  expect(p.size.height, greaterThanOrEqualTo(p.textSize.height - 0.01), reason: 'cut');
  if (oneLine) {
    expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.01));
  }
}

void main() {
  void largeText(WidgetTester tester) {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('at 2× text the Text options\' rows show their whole labels', (tester) async {
    largeText(tester);
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 320, child: TextOptionsPanel(tools: tools)),
          ),
        ),
      ),
    );
    _whole(tester, find.text('Paragraph spacing'));
    _whole(tester, find.text('Font'));
  });

  testWidgets('at 2× text the phone format bar\'s size stays on one line', (tester) async {
    largeText(tester);
    await openCanvas(
      tester,
      size: const Size(390, 844),
      seed: (s, nb) => s.elements.save([
        text(nb.id, const Offset(20, 120), const TextData(text: 'Hello', fontSize: 24), width: 300),
      ]),
    );
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(60, 130)]);
    await tester.pumpAndSettle();
    _whole(tester, find.byKey(const ValueKey('text-size')), oneLine: true);
    expect(find.text('24'), findsOneWidget);
  });

  /// A phone at 2× text editing a box holding a 2 × 2 table, with the
  /// caret in its first cell; the format bar's ⋯ opened.
  Future<void> openPhoneMore(WidgetTester tester) async {
    largeText(tester);
    final b = RichTextBuffer(const TextData());
    b.insertTable(0, 2, 2);
    await openCanvas(
      tester,
      size: const Size(390, 844),
      seed: (s, nb) => s.elements.save([
        text(nb.id, const Offset(20, 120), b.toData(const TextData()), width: 300),
      ]),
    );
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(60, 130)]);
    await tester.pumpAndSettle();
    final box = tester.widget<TableEditorLayer>(find.byType(TableEditorLayer)).box;
    box.enterCell(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  int rows(WidgetTester tester) =>
      tester.widget<TableEditorLayer>(find.byType(TableEditorLayer)).box.tableAt(0)!.rows;

  testWidgets('phones at 2× text: the ⋯ in a table has whole rows; Table… opens the table menu', (
    tester,
  ) async {
    await openPhoneMore(tester);
    for (final label in ['Table…', 'Paragraph spacing', 'None', 'Delete text box']) {
      _whole(tester, find.text(label), oneLine: true);
    }
    // One row each instead of the table's commands and the four spacings.
    expect(find.text('Insert row below'), findsNothing);
    expect(find.text('Small'), findsNothing);
    await tester.tap(find.text('Table…'));
    await tester.pumpAndSettle();
    // The tablet's table menu, its rows whole too (menus widen with large text).
    for (final c in ['Insert row above', 'Insert column right', 'Header row', 'Delete table']) {
      _whole(tester, find.text(c), oneLine: true);
    }
    await tester.tap(find.text('Insert row below'));
    await tester.pumpAndSettle();
    expect(rows(tester), 3);
  });

  testWidgets('phones at 2× text: the ⋯\'s Paragraph spacing opens the four and applies one', (
    tester,
  ) async {
    await openPhoneMore(tester);
    await tester.tap(find.text('Paragraph spacing'));
    await tester.pumpAndSettle();
    for (final s in ParagraphSpacing.values) {
      _whole(tester, find.text(s.label), oneLine: true);
    }
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();
    final session = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;
    expect(session.tools.textStyle.spacing, ParagraphSpacing.large);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Large'), findsOneWidget, reason: 'the current spacing as the caption');
  });
}

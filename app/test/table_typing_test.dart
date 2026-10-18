import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_cells.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/elements/text_layout_cache.dart';
import 'package:len/ink/fonts/text_fonts.dart';

/// A keystroke in a cell lays out that cell only (UX_AUDIT R26-19; the
/// timings are in `test/perf/table_typing_perf_test.dart`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TextData table(int rows) {
    final b = RichTextBuffer(const TextData(text: 'Intro'));
    final t = b.insertTable(5, rows, 4, header: true);
    for (var k = 0; k < t.cells; k++) {
      final s = 'cell $k';
      b.setCell(t.line + k, s, List.filled(s.length, SpanStyle.plain));
    }
    return b.toData(const TextData());
  }

  test('typing in a cell of a 200-row table lays out that cell alone', () {
    final data = table(200);
    final box = RichTextController(data)..wrapWidth = 600;
    addTearDown(box.dispose);
    final layouts = TextLayoutCache();
    addTearDown(layouts.dispose);
    final line = data.tables.first.lineOf(100, 1);
    box.enterCell(line, atEnd: true);
    layouts.of(box.data, 600);
    final before = TableLayout.debugCellLayouts;
    for (final typed in ['cell Xa', 'cell Xab', 'cell Xabc']) {
      box.setCell(line, TextData(text: typed), TextSelection.collapsed(offset: typed.length), (
        runFrom: -1,
        runTo: -1,
        deletes: false,
        composing: false,
        command: false,
      ));
      layouts.of(box.data, 600);
    }
    expect(TableLayout.debugCellLayouts - before, 3, reason: 'one new layout a keystroke');
    // And the box is laid out as it would be from scratch.
    final kept = TextLayout.layout(box.data, 600);
    addTearDown(kept.dispose);
    expect(kept.data.text.split('\n')[line], 'cell Xabc');
    expect(kept.tables.first.cells[kept.tables.first.index(100, 1)].data.text, 'cell Xabc');
  });

  test('cells are laid out again when a font loads or goes', () {
    final data = table(2);
    TextLayout.layout(data, 600).dispose();
    final before = TableLayout.debugCellLayouts;
    TextLayout.layout(data, 600).dispose();
    expect(TableLayout.debugCellLayouts, before);
    TextFonts.changes.value++;
    TextLayout.layout(data, 600).dispose();
    expect(TableLayout.debugCellLayouts - before, 8);
  });
}

@Tags(['perf'])
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/ink/elements/text_layout_cache.dart';

import 'support/big_library.dart' show bestUs;

/// Typing in a cell of a big table (UX_AUDIT R26-19): what a keystroke
/// costs the box's controller (the cell's text set, the box's plan made
/// again) and the session measuring the box, for tables of 50, 200 and
/// 1000 rows × 5 columns. Before cell layouts were kept, each keystroke
/// laid out every cell (about 2.5 ms per extra row in a debug build).
///
/// Run: `tool/heavy.sh nix develop .. -c flutter test test/perf/table_typing_perf_test.dart`.
void main() {
  test('a keystroke in a cell of a big table', () {
    final lines = <String>[];
    for (final rows in [50, 200, 1000]) {
      final b = RichTextBuffer(const TextData(text: 'Intro'));
      final t = b.insertTable(5, rows, 5, header: true);
      for (var k = 0; k < t.cells; k++) {
        final s = 'cell $k with a few words';
        b.setCell(t.line + k, s, List.filled(s.length, SpanStyle.plain));
      }
      final box = RichTextController(b.toData(const TextData()))..wrapWidth = 800;
      final layouts = TextLayoutCache();
      final line = t.lineOf(rows ~/ 2, 2);
      box.enterCell(line, atEnd: true);
      var typed = '';
      void keystroke() {
        typed += 'x';
        final cell = TextData(text: 'cell $typed');
        box.setCell(line, cell, TextSelection.collapsed(offset: cell.text.length), (
          runFrom: -1,
          runTo: -1,
          deletes: false,
          composing: false,
          command: false,
        ));
        layouts.of(box.data, 800);
      }

      keystroke(); // (Warm.)
      final us = bestUs(() {
        for (var i = 0; i < 10; i++) {
          keystroke();
        }
      }, runs: 3);
      lines.add('$rows rows × 5: ${(us / 10 / 1000).toStringAsFixed(2)} ms a keystroke');
      layouts.dispose();
      box.dispose();
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

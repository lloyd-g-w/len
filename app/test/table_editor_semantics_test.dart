import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';

import 'table_editor_test.dart' show boxController, openBox;

/// While a table is edited screen readers reach every cell, with its row
/// and column, and can move to one (UX_AUDIT R26-16).
void main() {
  testWidgets('every cell of the table edited is a node; tapping one edits it', (tester) async {
    final semantics = tester.ensureSemantics();
    final b = RichTextBuffer(const TextData(text: 'Shopping'));
    final t = b.insertTable(8, 2, 2, header: true);
    for (final (k, s) in ['Item', 'Qty', 'Milk', '2'].indexed) {
      b.setCell(t.line + k, s, List.filled(s.length, SpanStyle.plain));
    }
    await openBox(tester, b.toData(const TextData()));
    final box = boxController(tester);
    box.enterCell(t.line + 3, atEnd: true); // "2"
    await tester.pumpAndSettle();

    final header = find.bySemanticsLabel('Item');
    expect(header, findsOneWidget);
    final node = tester.getSemantics(header);
    expect(node.getSemanticsData().role, SemanticsRole.columnHeader);
    expect(node.getSemanticsData().hint, 'Column 1 header');
    final milk = tester.getSemantics(find.bySemanticsLabel('Milk'));
    expect(milk.getSemanticsData().role, SemanticsRole.cell);
    expect(milk.getSemanticsData().hint, 'Row 2, column 1');
    // The cell edited is its field, named by its place.
    expect(find.bySemanticsLabel(RegExp('Row 2, column 2')), findsOneWidget);
    // In a table node, in row nodes.
    var parent = milk.parent;
    expect(parent?.getSemanticsData().role, SemanticsRole.row);
    parent = parent?.parent;
    expect(parent?.getSemanticsData().role, SemanticsRole.table);

    milk.owner!.performAction(milk.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(box.activeCell, t.line + 2);
    semantics.dispose();
  });
}

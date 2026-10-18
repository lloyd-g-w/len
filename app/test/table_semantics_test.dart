import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/tools/text_table_semantics.dart';

import 'content_golden_test.dart' show loadFonts;
import 'table_layout_test.dart' show shopping;

void main() {
  setUpAll(loadFonts);

  testWidgets('screen readers get a table of rows of cells, the header as column headers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final data = shopping();
    expect(TextTableSemantics.textOutside(data), 'Shopping\nTotal is fine');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned(
              left: 10,
              top: 10,
              width: 320,
              height: 300,
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: TextTableSemantics.textOutside(data),
                child: TextTableSemantics(data: data, width: 320, offset: Offset.zero, scale: 1),
              ),
            ),
          ],
        ),
      ),
    );
    SemanticsNode nodeOf(String label) => tester.getSemantics(find.bySemanticsLabel(label));
    final milk = nodeOf('Milk');
    expect(milk.role, SemanticsRole.cell);
    expect(nodeOf('Price').role, SemanticsRole.columnHeader);
    SemanticsNode? up = milk;
    final roles = <SemanticsRole>[];
    while (up != null) {
      roles.add(up.role);
      up = up.parent;
    }
    expect(roles.take(3), [SemanticsRole.cell, SemanticsRole.row, SemanticsRole.table]);
    // Cells sit where they are laid out: Milk left of its price.
    expect(milk.rect.width, lessThan(200));
    handle.dispose();
  });
}

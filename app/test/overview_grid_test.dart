import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/overview/overview_grid.dart';

NotebookPage _page(int i, double w, double h) => NotebookPage(
  id: 'p$i',
  notebookId: 'n',
  sortKey: i.toDouble(),
  width: w,
  height: h,
  paper: Paper.blank,
);

/// The overview's cells take the shape of the notebook's pages (UX_AUDIT R18-3).
void main() {
  test('the common page shape wins; A4 without pages', () {
    expect(commonPageAspect(const []), a4Aspect);
    final deck = [for (var i = 0; i < 5; i++) _page(i, 960, 540), _page(9, 794, 1123)];
    expect(commonPageAspect(deck), closeTo(16 / 9, 0.01));
  });

  for (final (name, aspect) in [('slides', 16 / 9), ('A4', a4Aspect)]) {
    testWidgets('$name: a tile is its page, its ring and its number', (tester) async {
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewGrid(
              count: 6,
              compact: true,
              pageAspect: aspect,
              tile: (context, i, columns) => ColoredBox(key: ValueKey(i), color: Colors.grey),
            ),
          ),
        ),
      );
      final cell = tester.getSize(find.byKey(const ValueKey(0)));
      final page = (cell.width - OverviewGrid.ring) / aspect + OverviewGrid.ring;
      expect(
        cell.height,
        closeTo(page + OverviewGrid.footer(tester.element(find.byKey(const ValueKey(0)))), 0.5),
      );
      // Slides get wider cells: three across a portrait tablet, not four.
      if (aspect > 1) expect(cell.width, greaterThan(220));
    });
  }
}

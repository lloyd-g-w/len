import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/overview/overview_selection.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/labelled_action.dart';

/// The shared selection bar (UX_AUDIT R8-13): one size of names that
/// never touch; what doesn't fit goes into ⋯, else names go.
void main() {
  final ran = <SelectionAction>[];

  Future<void> pump(WidgetTester tester, double width, {double textScale = 1}) async {
    tester.view
      ..physicalSize = Size(width, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ran.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            bottomNavigationBar: PageSelectionBar(
              count: 2,
              total: 5,
              onClose: () {},
              onSelectAll: () {},
              onAction: ran.add,
              offered: SelectionAction.values.toSet(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<Rect> labelRects(WidgetTester tester) => [
    for (final e
        in find.descendant(of: find.byType(LabelledAction), matching: find.byType(Text)).evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ];

  void expectApart(List<Rect> rects) {
    for (var i = 1; i < rects.length; i++) {
      if (rects[i].top != rects[i - 1].top) continue;
      expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right), reason: 'labels touch');
    }
  }

  testWidgets('wide: one row, every name', (tester) async {
    await pump(tester, 1000);
    for (final name in ['Duplicate', 'Move or copy…', 'Bookmark', 'Change template…', 'Export…']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.byTooltip('More'), findsNothing);
    expectApart(labelRects(tester));
  });

  testWidgets('phone: Bookmark and Template go into ⋯; names one size, apart', (tester) async {
    await pump(tester, 390);
    expect(find.text('Bookmark'), findsNothing);
    expect(find.text('Change template…'), findsNothing);
    final rects = labelRects(tester);
    expect(rects, isNotEmpty);
    expect(rects.map((r) => r.height).toSet(), hasLength(1), reason: 'one size');
    expectApart(rects);
    expect(find.byType(LabelledAction), findsNWidgets(5));

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change template…'));
    await tester.pumpAndSettle();
    expect(ran, [SelectionAction.template]);
  });

  testWidgets('no room for names: glyphs alone, with tooltips', (tester) async {
    await pump(tester, 320, textScale: 2);
    expect(find.text('Export…'), findsNothing);
    expect(find.byTooltip('Export…'), findsOneWidget);
    // Move or copy…, Export…, Delete and ⋯.
    expect(find.byType(LabelledAction), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}

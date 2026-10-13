import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/tabs/notebook_tab_strip.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';
import 'package:len/ui/app_theme.dart';

import 'editor_tabs_test.dart' show notebook;

void main() {
  testWidgets('tabs past the edge fade and scroll; the active one shows in full', (tester) async {
    final tabs = OpenNotebooks();
    addTearDown(tabs.dispose);
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) {
      tabs.open(notebook(id).copyWith(title: id == 'f' ? 'Physics — Mechanics and waves' : null));
    }
    tabs.activate('a');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          // Loose width, as in the top bar's column.
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              child: Column(
                children: [SizedBox(height: 40, child: NotebookTabStrip(tabs: tabs))],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The tabs start at the leading edge, and a cut edge is faded.
    expect(tester.getRect(find.byKey(const ValueKey('tab-a'))).left, lessThan(16));
    expect(find.byKey(const ValueKey('scroll-fade')), findsOneWidget);

    // Activating the last tab scrolls it into view, and its long title
    // takes more room than an inactive tab's would.
    tabs.activate('f');
    await tester.pumpAndSettle();
    final f = tester.getRect(find.byKey(const ValueKey('tab-f')));
    expect(f.left, greaterThanOrEqualTo(0));
    expect(f.right, lessThanOrEqualTo(500));
    expect(f.width, greaterThan(NotebookTabStrip.maxWidth));
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/features/editor/outline/outline_panel.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

/// Phones reach the page overview from the bar (UX_AUDIT round 4, P1-10).
void main() {
  testWidgets('the phone bar has ▦; it opens all pages, and the outline is a filter there', (
    tester,
  ) async {
    await pumpEditor(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Outline'), findsNothing, reason: 'its home is the overview');
    await tester.tapAt(const Offset(200, 500)); // Close the menu.
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    expect(find.byType(PageOverview), findsOneWidget);
    expect(find.byKey(const ValueKey('page-tile-0')), findsOneWidget);
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect(find.byType(OutlinePanel), findsOneWidget);
    expect(find.text('Add page 1 to outline'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });
}

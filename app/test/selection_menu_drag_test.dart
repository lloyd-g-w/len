import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/tools/content_layer.dart';
import 'package:len/features/editor/tools/selection_menu.dart';

import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;

void main() {
  testWidgets('the selection menu steps aside during a drag and comes back where it went', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    await drawAt(tester, const Offset(400, 300));
    final ink = inkOf(s, s.pages.pagesOf(nb.id).first).last;
    final selection = tester.widget<ContentLayer>(find.byType(ContentLayer)).content.selection;
    selection.select([selection.model.strokeById(ink.id)!], const []);
    await tester.pumpAndSettle();
    final more = find.descendant(of: find.byType(SelectionMenu), matching: find.byTooltip('More'));
    final before = tester.getRect(more);

    final start = selection.frame!;
    for (var i = 1; i <= 5; i++) {
      final move = start.moved(Offset(i * 20.0, 0));
      selection.setPreview(move.transform, move.frame);
      await tester.pump();
      expect(more, findsNothing);
    }
    selection.commitPreview();
    await tester.pumpAndSettle();
    expect(tester.getRect(more).left, greaterThan(before.left + 50));
    expect(tester.getRect(more).top, closeTo(before.top, 1));

    selection.clear();
    await tester.pumpAndSettle();
    expect(more, findsNothing);
    await closeEditor(tester);
  });
}

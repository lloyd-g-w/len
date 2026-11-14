import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/chrome/title_button.dart';

import 'search_ui_test.dart' show pumpEditorFor;

/// UX_AUDIT R27-1: the editor's title and its folder fit the top bar.
void main() {
  for (final (size, name) in [(const Size(390, 844), 'phone'), (const Size(1280, 800), 'tablet')]) {
    testWidgets('$name: at large text the folder line gives way to the title', (tester) async {
      final s = AppServices.create(AppDatabase.inMemory());
      addTearDown(s.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final folder = s.folders.create(name: 'Calculus', color: 0xFF1971C2);
      final nb = s.notebooks.create(
        title: 'Lecture 12',
        kind: NotebookKind.paged,
        paper: PaperStyle.gridLarge,
        coverColor: 0xFF1971C2,
        folderId: folder.id,
      );
      final title = find.byType(TitleButton);

      await pumpEditorFor(tester, s, nb, size: size);
      expect(find.descendant(of: title, matching: find.text('Calculus')), findsOneWidget);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.descendant(of: title, matching: find.text('Calculus')), findsNothing);
      expect(find.descendant(of: title, matching: find.text('Lecture 12')), findsOneWidget);
      // Screen readers still hear where it is.
      expect(find.bySemanticsLabel('Lecture 12, Calculus'), findsOneWidget);
      // Inside the bar.
      final bar = tester.getRect(title);
      final text = tester.getRect(find.descendant(of: title, matching: find.byType(Column)));
      expect(text.bottom, lessThanOrEqualTo(bar.bottom + 0.01));
    });
  }
}

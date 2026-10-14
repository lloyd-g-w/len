import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';

import 'search_ui_test.dart' show pumpEditorFor;

void main() {
  // Found by the desktop e2e suite: closing the window exits the app
  // without hiding or disposing the editor, so its place and a text box
  // being typed were lost.
  testWidgets('closing the desktop window keeps the page and a text box being typed', (
    tester,
  ) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final nb = services.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    services.pages
      ..addPage(nb.id)
      ..addPage(nb.id);
    await pumpEditorFor(tester, services, nb);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    final view = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView));
    expect(view.controller.currentPage, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.tap(find.byType(PagedDocumentView));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('text-box-field')), 'Draft');
    await tester.pump();

    // What the Linux and Windows embedders send when the window closes.
    await tester.binding.handleRequestAppExit();

    final saved = EditorViewState.decode(services.settings.editorView(nb.id));
    expect(saved?.page, 2);
    final texts = services.database.db.select(
      "SELECT data FROM elements WHERE deleted = 0 AND type = 'text'",
    );
    expect(texts.single['data'], contains('Draft'));
  });

  // Strokes are written after the frame that shows them; a window closed
  // (or an app hidden, which stops frames) before that frame lost them.
  testWidgets('closing the window right after a stroke keeps the stroke', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final nb = services.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    await pumpEditorFor(tester, services, nb);
    int strokes() => services.database.db.select('SELECT id FROM strokes WHERE deleted = 0').length;
    expect(strokes(), 0);

    final pen = await tester.startGesture(const Offset(300, 400), kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 8; i++) {
      await pen.moveTo(Offset(300 + i * 8.0, 400 + i * 2.0));
    }
    await pen.up(); // No frame after it.
    await tester.binding.handleRequestAppExit();

    expect(strokes(), 1);
  });
}

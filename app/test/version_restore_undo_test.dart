import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/features/editor/document/page_models.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/history/version_flows.dart';
import 'package:len/ink/surface_model.dart';

import 'document_editor_test.dart' show closeEditor;
import 'split_view_test.dart' show drawIn, inkOfNotebook, paneOf, pumpWorkspace;

/// A restore drops the editor's undo steps of what it rewrote (UX_AUDIT
/// R25-6): its own Undo is the snack bar's.
void main() {
  Future<void> keys(WidgetTester tester, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Set<String> idsOf(AppServices s, Notebook n) => {for (final st in inkOfNotebook(s, n)) st.id};

  testWidgets('after a restore, Ctrl+Z and Ctrl+Shift+Z leave the restored pages alone; '
      'the other notebook keeps its steps', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();

    await drawIn(tester, 1); // Chemistry.
    await drawIn(tester, 0); // Physics: the version keeps this one.
    SurfaceModel.flushAll();
    late NotebookVersion version;
    await tester.runAsync(() async => version = (await s.versions.record(physics.id))!);
    final kept = idsOf(s, physics);
    expect(kept, hasLength(1));
    await drawIn(tester, 0, at: const Offset(-100, 80)); // Gone in the restore.
    SurfaceModel.flushAll();
    expect(idsOf(s, physics), hasLength(2));

    late Restored done;
    await tester.runAsync(() async => done = await s.versions.restore(version));
    announceRestore(s, physics.id, done, whole: true);
    await tester.pumpAndSettle();
    expect(idsOf(s, physics), kept);

    final doc = tester.widget<PagedDocumentView>(paneOf(0)).controller;
    expect(doc.surfaces.canUndo, isFalse, reason: 'the restored pages’ steps are gone');
    expect(doc.surfaces.canRedo, isFalse);
    await keys(tester); // Physics has the keyboard: it was drawn in last.
    await keys(tester, shift: true);
    SurfaceModel.flushAll();
    expect(idsOf(s, physics), kept, reason: 'no stroke taken out or written back');

    // The other notebook's step survived.
    final other = tester.widget<PagedDocumentView>(paneOf(1)).controller;
    expect(other.surfaces.canUndo, isTrue);
    other.surfaces.undo();
    await tester.pump(const Duration(milliseconds: 300));
    SurfaceModel.flushAll();
    expect(inkOfNotebook(s, chemistry), isEmpty);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  test('a whole-notebook restore drops page-level steps; a page restore keeps them', () {
    final models = PageModels();
    addTearDown(models.dispose);
    var undone = 0;
    models.record(PageEdit(undo: () => undone++, redo: () {}));
    models.forget({'p1'});
    expect(models.canUndo, isTrue, reason: 'one page restored');
    models.forget({'p1'}, pageEdits: true);
    expect(models.canUndo, isFalse);
    models.undo();
    expect(undone, 0);
  });
}

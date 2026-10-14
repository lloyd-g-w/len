import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

/// What happens after an editor closed: snack bars, pending work.
void main() {
  Future<(AppServices, Notebook)> pumpLibraryWithEditor(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    services.pages.addPage(nb.id);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => EditorScreen(notebook: nb))),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return (services, nb);
  }

  testWidgets('a page-delete snack bar\'s Undo still works after the editor closed', (
    tester,
  ) async {
    final (s, nb) = await pumpLibraryWithEditor(tester);
    final before = [for (final p in s.pages.pagesOf(nb.id)) p.id];
    expect(before, hasLength(2));

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete page').last);
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id), hasLength(1));
    expect(find.text('Undo'), findsOneWidget);

    // Back to the library; the snack bar stays.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect([for (final p in s.pages.pagesOf(nb.id)) p.id], before);
  });
}

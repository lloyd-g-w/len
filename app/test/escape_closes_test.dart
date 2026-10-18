import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/escape_closes.dart';

/// Full-screen routes close on Escape, as dialogs do (UX_AUDIT R25-8).
void main() {
  Future<void> pushOver(WidgetTester tester, Widget Function(BuildContext) page) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: page)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Escape pops the route, without a click first', (tester) async {
    await pushOver(tester, (_) => const EscapeCloses(child: Scaffold(body: Text('Page'))));
    expect(find.text('Page'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('the page overview: Escape leaves selecting first, then closes', (tester) async {
    tester.view
      ..physicalSize = const Size(1000, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'N',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await pushOver(
      tester,
      (_) => PageOverview(
        currentPage: 0,
        copier: SurfaceCopier(s.strokes, elements: s.elements),
        handlers: OverviewHandlers(
          load: () => s.pages.pagesOf(nb.id),
          move: s.pages.move,
          command: (context, command, page) async {},
        ),
      ),
    );
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Select pages'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Select pages'), findsNothing);
    expect(find.text('Select'), findsOneWidget, reason: 'still open');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Select'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('with a control in the page focused, Escape still closes it', (tester) async {
    await pushOver(
      tester,
      (_) => EscapeCloses(
        child: Scaffold(
          appBar: AppBar(title: const Text('Page')),
          body: TextButton(onPressed: () {}, child: const Text('Button')),
        ),
      ),
    );
    // Tab to the button: the focus is inside the Scaffold, whose drawer
    // action (off without a drawer) used to swallow Escape.
    FocusManager.instance.primaryFocus!.nextFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus!.context!.widget, isNot(isA<EscapeCloses>()));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsNothing);
  });

  testWidgets('in a text field, Escape leaves the field first, then closes', (tester) async {
    await pushOver(
      tester,
      (_) => const EscapeCloses(
        child: Scaffold(appBar: null, body: Column(children: [Text('Page'), TextField()])),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'typed');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsOneWidget, reason: 'what was typed is not lost to a stray key');
    expect(tester.testTextInput.hasAnyClients, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsNothing);
  });

  testWidgets('a menu open over the page: Escape closes the menu only', (tester) async {
    await pushOver(
      tester,
      (_) => EscapeCloses(
        child: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const Text('Page'),
                TextButton(
                  onPressed: () => showMenu<int>(
                    context: context,
                    position: RelativeRect.fill,
                    items: const [PopupMenuItem(value: 1, child: Text('Row'))],
                  ),
                  child: const Text('Menu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Row'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Row'), findsNothing);
    expect(find.text('Page'), findsOneWidget, reason: 'not popped twice');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsNothing);
  });
}

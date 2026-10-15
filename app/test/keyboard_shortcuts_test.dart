import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/settings/keyboard_shortcuts.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;
import 'ui_library_test.dart' show pumpLibrary;

/// Every activator bound by a [CallbackShortcuts] in the tree now.
Set<SingleActivator> boundNow(WidgetTester tester) => {
  for (final w in tester.widgetList<CallbackShortcuts>(find.byType(CallbackShortcuts)))
    ...w.bindings.keys.whereType<SingleActivator>(),
};

/// Whether [want] (written with `control` for Ctrl / ⌘) is in [bound].
bool isBound(Set<SingleActivator> bound, SingleActivator want) => bound.any(
  (b) =>
      b.trigger == want.trigger &&
      b.shift == want.shift &&
      b.alt == want.alt &&
      (b.control || b.meta) == (want.control || want.meta),
);

List<ShortcutHelp> group(String title) => shortcutGroups.firstWhere((g) => g.title == title).items;

/// The entries of [items] (but [except]) whose keys aren't all bound.
List<String> unbound(
  Set<SingleActivator> bound,
  Iterable<ShortcutHelp> items, {
  Set<String> except = const {},
}) => [
  for (final item in items)
    if (!except.contains(item.label))
      for (final key in item.keys)
        if (!isBound(bound, key)) '${item.label}: ${describeShortcut(key)}',
];

void main() {
  testWidgets('the reference lists only shortcuts the editor binds', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    // Tabs, search and focus mode bind theirs only while they exist.
    const later = {
      'Next / previous notebook',
      'Close notebook tab',
      'Next / previous match',
      'Turn pages in focus mode',
      // Bound by what has focus (a11y_context_menu_keys_test).
      'Context menu',
    };
    var bound = boundNow(tester);
    expect(unbound(bound, group('General'), except: later), isEmpty);
    expect(unbound(bound, group('Tools')), isEmpty);
    expect(unbound(bound, group('Selection')), isEmpty);
    // The overview binds its own (page_overview_test).
    expect(unbound(bound, group('Pages'), except: {'Move page in the overview'}), isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    bound = boundNow(tester);
    expect(
      unbound(bound, group('General').where((h) => h.label == 'Next / previous match')),
      isEmpty,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(
      unbound(
        boundNow(tester),
        group('General').where((h) => h.label == 'Turn pages in focus mode'),
      ),
      isEmpty,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();

    // A text box being edited.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.tapAt(const Offset(500, 400));
    await tester.pumpAndSettle();
    expect(unbound(boundNow(tester), group('Text boxes')), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('… and a canvas and the library bind theirs', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.dotted,
      coverColor: 0,
    );
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(unbound(boundNow(tester), group('Canvas')), isEmpty);
    await closeEditor(tester);

    await pumpLibrary(tester);
    expect(unbound(boundNow(tester), group('Library')), isEmpty);
    expect(
      unbound(boundNow(tester), group('General').where((h) => h.label == 'Keyboard shortcuts')),
      isEmpty,
    );
  });

  testWidgets('Ctrl+/ opens the reference in the editor', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsWidgets);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Ctrl+Z'), findsOneWidget);
    expect(find.text('Ctrl+Shift+Z or Ctrl+Y'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('Ctrl+/ opens the reference in Settings too ("anywhere")', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppScope(services: services, child: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Ctrl+Shift+Z or Ctrl+Y'), findsOneWidget);
  });

  test('keys read as people write them', () {
    expect(describeShortcut(const SingleActivator(LogicalKeyboardKey.arrowRight)), '→');
    expect(describeShortcut(const SingleActivator(LogicalKeyboardKey.pageDown)), 'Page Down');
    expect(
      describeShortcut(const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true)),
      'Ctrl+Shift+Z',
    );
    expect(
      describeShortcut(const SingleActivator(LogicalKeyboardKey.slash, control: true)),
      'Ctrl+/',
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/tag.dart';
import 'package:len/features/library/library_query.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/ui/sidebar_item.dart';

import 'library_ui_test.dart' show addNotebook, openMenuOf, pumpSeeded;

void main() {
  group('LibraryQuery.parse', () {
    test('splits tag terms from text', () {
      void check(String query, String text, List<String> tags) {
        final parsed = LibraryQuery.parse(query);
        expect(parsed.text, text);
        expect(parsed.tags, tags);
      }

      check('maths tag:School  notes', 'maths notes', ['school']);
      check('tag:"home work" tag:x', '', ['home work', 'x']);
      check('notag:x', 'notag:x', []);
      check('tag:', '', []);
    });

    test('tag terms match tag name prefixes, all required', () {
      expect(LibraryQuery.hasTags(['Work', 'Urgent'], ['wo']), isTrue);
      expect(LibraryQuery.hasTags(['Work'], ['wo', 'urg']), isFalse);
      expect(LibraryQuery.hasTags([], []), isTrue);
    });
  });

  testWidgets('tag a notebook from its menu, filter by sidebar, chips and tag: search', (
    tester,
  ) async {
    final services = await pumpSeeded(tester, (s) {
      addNotebook(s, 'Algebra');
      addNotebook(s, 'Recipes');
      final home = s.tags.create(name: 'Home', color: 0xFF0CA678);
      final recipes = s.notebooks.list().firstWhere((n) => n.title == 'Recipes');
      s.tags.taggings.set(home.id, recipes.id, TagTarget.notebook, on: true);
    });

    // Create a tag in the picker by typing its name.
    await openMenuOf(tester, 'Algebra');
    await tester.tap(find.text('Tags…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tag-picker-field')), 'School');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-picker-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    final school = services.tags.byName('school')!;
    final algebra = services.notebooks.list().firstWhere((n) => n.title == 'Algebra');
    expect(services.tags.taggings.tagsOf(algebra.id), {school.id});

    // Sidebar: a Tags section with counts; tapping a tag filters.
    final schoolItem = find.widgetWithText(SidebarItem, 'School');
    expect(schoolItem, findsOneWidget);
    await tester.tap(schoolItem);
    await tester.pumpAndSettle();
    expect(find.byType(NotebookCard), findsOneWidget);
    expect(find.text('Algebra'), findsWidgets);
    expect(find.text('Recipes'), findsNothing);

    // Chips: the Home chip added to the School filter narrows to nothing.
    await tester.tap(find.byKey(ValueKey('tag-chip-${services.tags.byName('home')!.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookCard), findsNothing);
    expect(find.text('No tagged notebooks'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookCard), findsNWidgets(2));

    // Search: `tag:` narrows by tag name prefix.
    await tester.enterText(find.byType(TextField).first, 'tag:ho');
    await tester.pumpAndSettle();
    expect(find.byType(NotebookCard), findsOneWidget);
    expect(find.text('Recipes'), findsWidgets);
  });

  testWidgets('the tag manager renames and deletes tags', (tester) async {
    final services = await pumpSeeded(tester, (s) {
      final n = addNotebook(s, 'Algebra');
      final t = s.tags.create(name: 'Old', color: 0xFF0CA678);
      s.tags.taggings.set(t.id, n.id, TagTarget.notebook, on: true);
    });
    await tester.tap(find.byTooltip('Manage tags').first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('1 notebook')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'New');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(services.tags.list().single.name, 'New');

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(services.tags.list(), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SidebarItem, 'New'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'screenshot_harness.dart';

/// A year of notes (UX_AUDIT round 16): ~300 notebooks in nested folders,
/// written over twelve months, some trashed, some favourites.
void main() {
  setUpAll(loadRealFonts);

  const phone = Size(390, 844);
  const tablet = Size(1280, 800);
  const desktop = Size(1440, 900);

  testWidgets('year: library root phone, tablet, desktop', (tester) async {
    for (final (name, size, dpr) in [
      ('phone', phone, 2.0),
      ('tablet', tablet, 1.0),
      ('desktop', desktop, 1.0),
    ]) {
      setWindow(tester, size, dpr: dpr);
      final services = yearServices();
      await pumpApp(tester, services, const LibraryScreen());
      await shoot(tester, 'year_root_$name');
      await tester.pumpWidget(const SizedBox());
      services.dispose();
    }
  });

  testWidgets('year: deep folder, search, trash (tablet)', (tester) async {
    setWindow(tester, tablet);
    final services = yearServices();
    addTearDown(services.dispose);
    await pumpApp(tester, services, const LibraryScreen());
    await tester.tap(find.text('Year 1').first);
    await settle(tester);
    await shoot(tester, 'year_folder_year1');
    await tester.tap(find.text('Spring').first);
    await settle(tester);
    await tester.tap(find.text('Calculus').first);
    await settle(tester);
    await shoot(tester, 'year_folder_calculus');
    await tester.enterText(find.byType(TextField), 'lecture 3');
    await settle(tester);
    await shoot(tester, 'year_search_lecture3');
    await tester.enterText(find.byType(TextField), 'march');
    await settle(tester);
    await shoot(tester, 'year_search_march');
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);
    await tester.tap(find.text('Trash').first);
    await settle(tester);
    await shoot(tester, 'year_trash');
    expect(tester.takeException(), isNull);
  });

  testWidgets('year: phone drawer and move', (tester) async {
    setWindow(tester, phone, dpr: 2);
    final services = yearServices();
    addTearDown(services.dispose);
    await pumpApp(tester, services, const LibraryScreen());
    await openLibrarySection(tester, 'Year 1');
    await shoot(tester, 'year_phone_year1');
    for (final scaffold in tester.stateList<ScaffoldState>(find.byType(Scaffold))) {
      if (scaffold.hasDrawer) scaffold.openDrawer();
    }
    await settle(tester);
    await shoot(tester, 'year_phone_drawer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('year: settings (tablet)', (tester) async {
    setWindow(tester, tablet);
    final services = yearServices();
    addTearDown(services.dispose);
    await pumpApp(tester, services, const SettingsScreen());
    await shoot(tester, 'year_settings');
    expect(tester.takeException(), isNull);
  });
}

const _courses = {
  'Autumn': ['Calculus', 'Physics', 'Chemistry', 'Programming'],
  'Spring': ['Calculus', 'Linear algebra', 'Statistics', 'Electronics'],
  'Summer': ['Project'],
};

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// ~300 notebooks: Year 1 › term › course › "Calculus — Lecture 12", a
/// journal per month, work notes, some with ink.
AppServices yearServices() {
  final clock = ShotClock();
  final start = DateTime(2025, 10, 6, 9);
  clock.now = start.millisecondsSinceEpoch;
  final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  final year = s.folders.create(name: 'Year 1', color: Palette.covers[0]);
  final personal = s.folders.create(name: 'Personal', color: Palette.covers[4]);
  final work = s.folders.create(name: 'Part-time job', color: Palette.covers[1]);
  var color = 0;
  Notebook nb(String title, String? folder, DateTime at, {bool ink = false}) {
    clock.now = at.millisecondsSinceEpoch;
    final n = s.notebooks.create(
      title: title,
      kind: NotebookKind.paged,
      paper: PaperStyle.wideRuled,
      coverColor: Palette.covers[color++ % Palette.covers.length],
      folderId: folder,
    );
    if (ink)
      s.strokes.save(handwriting(s.pages.pagesOf(n.id).first.id, clock, lines: 6, canvas: false));
    return n;
  }

  final recent = <String>[];
  var term = 0;
  for (final MapEntry(key: termName, value: courses) in _courses.entries) {
    final termFolder = s.folders.create(
      name: termName,
      parentId: year.id,
      color: Palette.covers[2],
    );
    final termStart = start.add(Duration(days: 120 * term++));
    for (final (ci, course) in courses.indexed) {
      final folder = s.folders.create(
        name: course,
        parentId: termFolder.id,
        color: Palette.covers[(ci + 3) % Palette.covers.length],
      );
      final lectures = termName == 'Summer' ? 10 : 22;
      for (var i = 1; i <= lectures; i++) {
        final n = nb(
          '$course — Lecture $i',
          folder.id,
          termStart.add(Duration(days: i * 5, hours: ci)),
          ink: i % 7 == 0,
        );
        if (termName == 'Spring' && i > lectures - 2) recent.add(n.id);
      }
      nb('$course — Exam prep', folder.id, termStart.add(Duration(days: 110, hours: ci)));
    }
  }
  for (var m = 0; m < 12; m++) {
    final month = DateTime(2025, 10 + m);
    nb('Journal — ${_months[month.month - 1]} ${month.year}', personal.id, month, ink: m == 11);
  }
  for (var i = 1; i <= 14; i++) {
    nb('Shift notes $i', work.id, start.add(Duration(days: i * 25)));
  }
  final loose = ['Ideas', 'Reading list', 'Sketches', 'Untitled', 'Untitled 2', 'Quick notes'];
  for (final (i, title) in loose.indexed) {
    nb(title, null, start.add(Duration(days: 40 * i + 3)), ink: i == 0);
  }
  final all = s.notebooks.list();
  for (final n in all.take(30)) {
    if (n.title.endsWith('Lecture 2')) s.notebooks.setFavorite(n.id, true);
  }
  for (final n in all.where((n) => n.title.startsWith('Shift notes 1'))) {
    s.notebooks.trash(n.id);
  }
  clock.now = DateTime(2026, 10, 10, 9, 30).millisecondsSinceEpoch;
  s.settings.recentNotebooks = recent.reversed.toList();
  return s;
}

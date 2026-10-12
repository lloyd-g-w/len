import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/ui/app_theme.dart';

import '../screenshots/screenshot_harness.dart' show ShotClock, handwriting;

/// A library of 200 notebooks, half of them with ink: the grid builds only
/// what is near the screen, covers render lazily (those on screen first),
/// and scrolling through all of it stays cheap.
void main() {
  testWidgets('200 notebooks: lazy grid and covers, cheap scrolling', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clock = ShotClock();
    final services = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(services.dispose);
    for (var i = 0; i < 200; i++) {
      final n = services.notebooks.create(
        title: 'Notebook $i',
        kind: NotebookKind.paged,
        paper: PaperStyle.collegeRuled,
        coverColor: Palette.covers[i % Palette.covers.length],
      );
      if (i.isEven) {
        final page = services.pages.pagesOf(n.id).first.id;
        services.strokes.save(handwriting(page, clock, lines: 3, canvas: false));
      }
    }

    final watch = Stopwatch()..start();
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(theme: AppTheme.light(), home: const LibraryScreen()),
      ),
    );
    final firstFrame = watch.elapsedMilliseconds;
    await tester.pumpAndSettle();

    // Only a few screens' worth of cards exist (6 columns, ~3 rows a screen).
    final built = find.byType(NotebookCard, skipOffstage: false).evaluate().length;
    expect(built, lessThan(60));

    // Scroll to the end in steps, as a fling would, timing every frame.
    final frames = <int>[];
    var maxBuilt = built;
    final rebuilt = <String, int>{};
    debugOnRebuildDirtyWidget = (e, _) =>
        rebuilt.update(e.widget.runtimeType.toString(), (n) => n + 1, ifAbsent: () => 1);
    for (var i = 0; i < 40; i++) {
      final frame = Stopwatch()..start();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(frame.elapsedMicroseconds);
      final now = find.byType(NotebookCard, skipOffstage: false).evaluate().length;
      if (now > maxBuilt) maxBuilt = now;
    }
    debugOnRebuildDirtyWidget = null;
    // Each frame builds only the cards scrolling in (a row or two of six),
    // never the whole grid again.
    final cardBuilds = rebuilt['NotebookCard'] ?? 0;
    expect(cardBuilds, lessThan(40 * 14));
    await tester.pumpAndSettle();
    expect(find.text('Notebook 0'), findsOneWidget, reason: 'the last notebook (oldest) shows');
    expect(maxBuilt, lessThan(60), reason: 'cards scrolled past are disposed');
    expect(tester.takeException(), isNull);

    frames.sort();
    // ignore: avoid_print
    print(
      'library, 200 notebooks: first frame ${firstFrame}ms; scroll frames '
      'median ${frames[frames.length ~/ 2] ~/ 1000}ms, '
      'p90 ${frames[frames.length * 9 ~/ 10] ~/ 1000}ms (debug, renders included); '
      'at most $maxBuilt cards alive, $cardBuilds card builds in 40 frames',
    );
  });
}

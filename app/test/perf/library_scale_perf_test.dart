import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/library/library_content.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/ui/app_theme.dart';

import 'support/big_library.dart';

/// A years-old library: 1,000 notebooks in 50 folders (100 favourites,
/// 200 in the trash), 10,000 pages of typed and PDF text, a page of
/// handwriting on every cover. Opening, scrolling, searching as you type
/// and switching sort and layout stay within a few frames.
void main() {
  testWidgets('1,000 notebooks: open, scroll, search as you type, sort', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clock = BenchClock();
    final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    BigLibrary.build(s, clock);

    final watch = Stopwatch()..start();
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(theme: AppTheme.light(), home: const LibraryScreen()),
      ),
    );
    final firstFrame = watch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    final settled = watch.elapsedMilliseconds;
    final controller = tester
        .widget<LibraryContent>(find.byType(LibraryContent))
        .actions
        .controller;
    // The library root: notebooks outside folders, and the top folders.
    final built = find.byType(NotebookCard, skipOffstage: false).evaluate().length;
    expect(built, lessThan(60));

    // Scroll the root (folders and the notebooks outside them).
    final frames = <int>[];
    final rebuilt = <String, int>{};
    debugOnRebuildDirtyWidget = (e, _) =>
        rebuilt.update(e.widget.runtimeType.toString(), (n) => n + 1, ifAbsent: () => 1);
    for (var i = 0; i < 40; i++) {
      final frame = Stopwatch()..start();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(frame.elapsedMilliseconds);
    }
    debugOnRebuildDirtyWidget = null;
    frames.sort();
    await tester.pumpAndSettle();
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 20000), 20000);
    await tester.pumpAndSettle();

    // Search as you type: one frame per key (the content search is
    // debounced), then the results.
    final keys = <int>[];
    var typed = '';
    for (final ch in 'meeting'.split('')) {
      typed += ch;
      final key = Stopwatch()..start();
      await tester.enterText(find.byType(TextField).first, typed);
      await tester.pump(const Duration(milliseconds: 16));
      keys.add(key.elapsedMilliseconds);
    }
    watch.reset();
    await tester.pump(const Duration(milliseconds: 200));
    final results = watch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    // Sort and layout switches rebuild the grid once.
    final switches = <String, int>{};
    for (final sort in LibrarySort.values) {
      watch.reset();
      controller.sort = sort;
      await tester.pump();
      switches['sort ${sort.name}'] = watch.elapsedMilliseconds;
    }
    for (final layout in [LibraryLayout.list, LibraryLayout.grid]) {
      watch.reset();
      controller.layout = layout;
      await tester.pump();
      switches['layout ${layout.name}'] = watch.elapsedMilliseconds;
    }
    watch.reset();
    controller.reload();
    await tester.pump();
    switches['reload'] = watch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    report(
      'library, 1,000 notebooks: first frame ${firstFrame}ms, settled ${settled}ms; '
      'scroll frames median ${frames[frames.length ~/ 2]}ms, max ${frames.last}ms, '
      '${rebuilt['NotebookCard'] ?? 0} card builds in 40 frames; search keys '
      '${keys.join('/')}ms, results ${results}ms; $switches (debug, renders included)',
    );
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 5)));
}

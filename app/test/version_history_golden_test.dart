import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/history/version_history_sheet.dart';
import 'package:len/features/history/version_surface_view.dart';
import 'package:len/ui/app_theme.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'content_golden_test.dart' show loadFonts, text;
import 'support/handwriting.dart';
import 'support/real_async.dart';

/// Fixed time (Saturday 17 Oct 2026, 14:30) and ids, so days, times and
/// the goldens are stable.
class _Clock extends Clock {
  int now = DateTime(2026, 10, 17, 14, 30).millisecondsSinceEpoch;
  int _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'id${_ids++}';
}

/// Lines of cursive "words" on [surface], from [top] down.
List<Stroke> _lines(String surface, String id, int seed, {double top = 200, int lines = 4}) => [
  for (var l = 0; l < lines; l++)
    for (var w = 0; w < 4; w++)
      Stroke(
        id: '$id-$l-$w',
        surfaceId: surface,
        tool: InkTool.ballpoint,
        color: 0xFF1F2937,
        width: 3,
        points: Handwriting(seed: seed + l * 4 + w).cursive(Offset(80.0 + w * 160, top + l * 64), [
          for (var j = 0; j < 4 + (w + l) % 3; j++) (height: j.isEven ? 22.0 : 40.0, loop: 5.0),
        ], letterWidth: 20),
        createdAt: 1,
      ),
];

Stroke _underline(String surface, String id, double y, int color) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: color,
  width: 5,
  points: Handwriting(seed: 3).line(Offset(80, y), Offset(520, y + 4)),
  createdAt: 1,
);

void main() {
  late _Clock clock;
  late AppServices s;
  late Notebook notebook;
  late NotebookVersion named;

  /// A three-page notebook with a version yesterday, one this morning and
  /// one named "Before the exam" (real time: packs are hashed in an
  /// isolate).
  Future<void> threeVersions(WidgetTester tester) async {
    clock = _Clock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    notebook = s.notebooks.create(
      title: 'Organic chemistry',
      kind: NotebookKind.paged,
      paper: PaperStyle.wideRuled,
      coverColor: 0xFF336699,
    );
    s.pages
      ..addPage(notebook.id, paper: notebook.paper)
      ..addPage(notebook.id, paper: notebook.paper);
    final pages = [for (final p in s.pages.pagesOf(notebook.id)) p.id];
    final today = clock.now;
    await tester.runAsync(() async {
      s.elements.save([
        text(
          pages[0],
          const Offset(80, 70),
          TextData.rich(text: 'Alkenes', paras: const [ParaStyle(heading: 1)]),
          width: 400,
        ),
      ]);
      s.strokes.save([
        _underline(pages[0], 'u0', 150, 0xFF1C7ED6),
        ..._lines(pages[0], 'p0', 10, lines: 6),
        ..._lines(pages[1], 'p1', 40, top: 120, lines: 3),
      ]);
      clock.now = today - const Duration(days: 1, hours: 4, minutes: 12).inMilliseconds;
      await s.versions.record(notebook.id);

      s.strokes.save([
        ..._lines(pages[1], 'p1b', 70, top: 330, lines: 4),
        ..._lines(pages[2], 'p2', 100, top: 120, lines: 2),
      ]);
      clock.now = today - const Duration(hours: 5, minutes: 25).inMilliseconds;
      await s.versions.record(notebook.id);

      s.strokes.save([
        _underline(pages[2], 'u2', 290, 0xFFE03131),
        ..._lines(pages[2], 'p2b', 130, top: 380, lines: 3),
      ]);
      clock.now = today - const Duration(hours: 2, minutes: 48).inMilliseconds;
      named = (await s.versions.save(notebook.id, name: 'Before the exam'))!;
      clock.now = today;
    });
    expect(s.versions.of(notebook.id), hasLength(3));
  }

  /// Every version thumbnail on screen has its page loaded (not the blank
  /// sheet shown while loading, nor the cloud-off one).
  bool loaded({int? count}) {
    final views = find.byType(VersionSurfaceView);
    final paints = find
        .descendant(of: views, matching: find.byType(CustomPaint))
        .evaluate()
        .map((e) => (e.widget as CustomPaint).painter)
        .where((p) => p != null)
        .toList();
    return paints.isNotEmpty &&
        (count == null || paints.length == count) &&
        // ignore: avoid_dynamic_calls
        paints.every((p) => (p as dynamic).sheet != null);
  }

  Future<void> open(WidgetTester tester, {required Size size, required bool dark}) async {
    await loadFonts();
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showVersionHistory(context, s, notebook.id),
                child: const Text('History'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => loaded(count: 3), stable: 2, reason: 'the thumbnails');
    await tester.pumpAndSettle();
  }

  for (final (device, size) in [
    ('tablet', const Size(1280, 800)),
    ('phone', const Size(390, 844)),
  ]) {
    for (final dark in [false, true]) {
      final name = '$device${dark ? '_dark' : ''}';

      testWidgets('version history on a $name', (tester) async {
        await threeVersions(tester);
        await open(tester, size: size, dark: dark);
        expect(find.text('Before the exam'), findsOneWidget);
        expect(find.byIcon(Symbols.cloud_off_sharp), findsNothing);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/version_history_$name.png'),
        );
      });

      testWidgets('version preview on a $name', (tester) async {
        await threeVersions(tester);
        await open(tester, size: size, dark: dark);
        await tester.tap(find.byKey(ValueKey('version-${named.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('version-${named.id}')), findsNothing, reason: 'covered');
        await pumpUntil(tester, () => loaded(count: 3), stable: 2, reason: 'the pages');
        expect(find.byIcon(Symbols.cloud_off_sharp), findsNothing);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/version_preview_$name.png'),
        );
      });
    }
  }
}

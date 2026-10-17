// The history's reach (UX_AUDIT round 25): screen readers and the
// keyboard open versions and pages, a double tap copies once, Delete
// version can be undone where it can be seen, and pages show their
// backgrounds (scans, PDFs).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/history/version_history_sheet.dart';
import 'package:len/ui/app_theme.dart';

import 'support/real_async.dart';

class _Clock extends Clock {
  int now = DateTime(2026, 10, 1, 14, 2).millisecondsSinceEpoch;
  int _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'id${_ids++}';
}

Stroke _ink(String id, String surface) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 3,
  points: const [StrokePoint(10, 10, 0.5), StrokePoint(40, 40, 0.5)],
  createdAt: 1,
);

void main() {
  late _Clock clock;
  late AppServices s;
  late Notebook notebook;
  final shot = GlobalKey();
  List<String> pageIds() => [for (final p in s.pages.pagesOf(notebook.id)) p.id];

  /// A notebook of a blank page and a red scan, with two versions.
  Future<void> setUpNotebook(WidgetTester tester) async {
    clock = _Clock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    notebook = s.notebooks.create(
      title: 'Lab book',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF336699,
    );
    await tester.runAsync(() async {
      final red = img.Image(width: 30, height: 40)..clear(img.ColorRgb8(220, 0, 0));
      final scan = await s.blobs.putBytes(img.encodePng(red), mime: 'image/png');
      s.pages.insertPages(notebook.id, [
        (
          size: const Size(300, 400),
          paper: Paper.blank,
          color: PaperColor.white,
          background: PageBackground.image(blob: scan),
        ),
      ]);
      final pages = [for (final p in s.pages.pagesOf(notebook.id)) p.id];
      for (var i = 0; i < 2; i++) {
        s.strokes.save([_ink('s$i', pages[i])]);
        clock.now += 60000;
        await s.versions.record(notebook.id);
      }
    });
  }

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          theme: AppTheme.light(),
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
      ),
    );
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
  }

  Future<void> openPreview(WidgetTester tester) async {
    final v = s.versions.of(notebook.id).first;
    await tester.tap(find.byKey(ValueKey('version-${v.id}')));
    await tester.pumpAndSettle();
  }

  testWidgets('screen readers open a version, its ⋯ and a page of it', (tester) async {
    final handle = tester.ensureSemantics();
    await setUpNotebook(tester);
    await open(tester, const Size(1200, 900));
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Edited, 14:04'))),
      isSemantics(isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.byTooltip('Version options').first),
      isSemantics(tooltip: 'Version options', isButton: true, hasTapAction: true),
    );
    await openPreview(tester);
    final tile = find.byKey(ValueKey('version-page-${pageIds().last}'));
    expect(
      tester.getSemantics(tile),
      isSemantics(isButton: true, hasTapAction: true, label: 'Page 2 of 2'),
    );
    handle.dispose();
  });

  testWidgets('the keyboard opens a page of the preview', (tester) async {
    await setUpNotebook(tester);
    await open(tester, const Size(1200, 900));
    await openPreview(tester);
    for (var i = 0; i < 12 && find.text('Page 1 of 2').evaluate().isEmpty; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus?.context;
      final onTile =
          focus != null &&
          find
              .ancestor(of: find.byWidget(focus.widget), matching: find.byType(GridView))
              .evaluate()
              .isNotEmpty;
      if (onTile) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }
    }
    expect(find.text('Page 1 of 2'), findsOneWidget);
  });

  testWidgets('a second Copy while the first copies is ignored', (tester) async {
    await setUpNotebook(tester);
    await open(tester, const Size(1200, 900));
    await openPreview(tester);
    final copy = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Copy as new notebook'));
    copy.onPressed!();
    copy.onPressed!();
    await pumpUntil(tester, () => s.notebooks.list().length >= 2, reason: 'a copy');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(s.notebooks.list(), hasLength(2));
  });

  testWidgets('Delete version is said on a phone’s sheet, with Undo', (tester) async {
    await setUpNotebook(tester);
    await open(tester, const Size(390, 844));
    final v = s.versions.of(notebook.id).first;
    await tester.tap(find.byTooltip('Version options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete version'));
    await tester.pumpAndSettle();
    expect(s.versions.of(notebook.id).map((x) => x.id), isNot(contains(v.id)));
    expect(find.text('Version deleted'), findsOneWidget);
    await tester.tap(find.text('Undo').hitTestable());
    await tester.pumpAndSettle();
    expect(s.versions.of(notebook.id).map((x) => x.id), contains(v.id));
  });

  testWidgets('a phone’s page view keeps its title at 2× text (Restore under the page)', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await setUpNotebook(tester);
    await open(tester, const Size(390, 844));
    await openPreview(tester);
    await tester.tap(find.byKey(ValueKey('version-page-${pageIds().last}')));
    await tester.pumpAndSettle();
    final title = tester.getRect(find.text('Page 2 of 2'));
    final restore = tester.getRect(find.widgetWithText(FilledButton, 'Restore this page'));
    expect(title.width, greaterThan(100));
    expect(restore.top, greaterThan(400), reason: 'the action sits under the page');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page’s scan shows in the preview', (tester) async {
    await setUpNotebook(tester);
    await open(tester, const Size(1200, 900));
    await openPreview(tester);
    final tile = find.byKey(ValueKey('version-page-${pageIds().last}'));
    final centre = tester.getCenter(tile) - const Offset(0, 12);
    Future<ui.Color> pixel() async {
      await tester.pump();
      return (await tester.runAsync(() async {
        final boundary = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData())!;
        final i = (centre.dy.round() * image.width + centre.dx.round()) * 4;
        return ui.Color.fromARGB(
          255,
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        );
      }))!;
    }

    late ui.Color seen;
    for (var i = 0; i < 50; i++) {
      seen = await pixel();
      if (seen.r > 0.7 && seen.g < 0.2) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    expect((seen.r > 0.7, seen.g < 0.2), (true, true), reason: 'red scan, saw $seen');
  });
}

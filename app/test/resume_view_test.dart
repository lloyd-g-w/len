import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/resume_view.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';

import 'data_test.dart' show FakeClock, stroke;

/// Where a notebook opens after another device wrote in it (UX_AUDIT R16-4).
void main() {
  late FakeClock clock;
  late AppServices s;
  late Notebook notebook;
  late List<String> pages;

  setUp(() {
    clock = FakeClock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    notebook = s.notebooks.create(
      title: 'Calculus',
      kind: NotebookKind.paged,
      paper: PaperStyle.wideRuled,
      coverColor: 0xFF000000,
    );
    for (var i = 0; i < 3; i++) {
      s.pages.addFreshPage(notebook);
    }
    pages = [for (final p in s.pages.pagesOf(notebook.id)) p.id];
  });
  tearDown(() => s.dispose());

  /// Ink on page [index] at [at], as another device ([device]) wrote it.
  void write(int index, int at, {String device = 'tablet'}) {
    clock.now = at;
    final id = 'stroke-$index-$at';
    s.strokes.save([stroke(id, const Offset(10, 10), surface: pages[index])]);
    s.database.execute('UPDATE strokes SET device_id = ? WHERE id = ?', [device, id]);
  }

  void keep(int page, int at) => s.settings.setEditorView(
    notebook.id,
    EditorViewState(scale: 2, offset: const Offset(5, 5), page: page, savedAt: at).encode(),
  );

  test('opens as this device left it when nobody wrote since', () {
    write(3, 1000);
    keep(1, 2000);
    final view = resumeView(s, notebook)!;
    expect(view.page, 1);
    expect(view.scale, 2);
  });

  test('opens on the page another device wrote on after this one left', () {
    keep(1, 2000);
    write(2, 3000);
    write(3, 4000);
    final view = resumeView(s, notebook)!;
    expect(view.page, 3);
    expect(view.fitsSize(const Size(800, 600)), isFalse); // Framed, not restored.
  });

  test('a notebook never opened here opens where it was written last', () {
    write(2, 3000);
    write(1, 2500);
    expect(resumeView(s, notebook)!.page, 2);
  });

  test('ink from a device whose clock runs fast, seen here, does not keep moving it', () {
    const hour = 3600 * 1000;
    write(2, 1000 + hour); // The tablet's clock is an hour ahead.
    clock.now = 3000; // This device looked, went to page 0, and left.
    keep(0, leftAt(s, notebook.id));
    expect(resumeView(s, notebook)!.page, 0);
    // What it writes later still counts.
    write(3, 1000 + 2 * hour);
    expect(resumeView(s, notebook)!.page, 3);
  });

  test('ink from a device whose clock runs slow, written after this one left, moves it', () {
    const hour = 3600 * 1000;
    write(2, 1000); // The tablet's clock is an hour behind this device's.
    clock.now = 1000 + hour; // This device looked, went to page 0, and left.
    keep(0, leftAt(s, notebook.id));
    expect(resumeView(s, notebook)!.page, 0);
    write(3, 2000); // Written later, by the tablet's clock.
    expect(resumeView(s, notebook)!.page, 3);
  });

  test('erased ink from elsewhere, seen here, counts as seen', () {
    write(2, 5000);
    s.database.execute('UPDATE strokes SET deleted = 1 WHERE surface_id = ?', [pages[2]]);
    write(1, 1000);
    clock.now = 500; // This device's clock runs slow.
    keep(0, leftAt(s, notebook.id));
    write(3, 4000); // Older than what was seen: written before this device left.
    expect(resumeView(s, notebook)!.page, 0);
  });

  test('ink this device wrote, or erased ink, does not move it', () {
    keep(0, 2000);
    write(3, 3000, device: s.strokes.deviceId);
    expect(resumeView(s, notebook)!.page, 0);
    write(2, 4000);
    s.database.execute('UPDATE strokes SET deleted = 1 WHERE surface_id = ?', [pages[2]]);
    expect(resumeView(s, notebook)!.page, 0);
  });

  test('without any ink from elsewhere nothing is kept or changed', () {
    expect(resumeView(s, notebook), isNull);
  });

  test('the time a view was kept survives encoding', () {
    final view = EditorViewState.decode(
      const EditorViewState(scale: 1, offset: Offset.zero, savedAt: 1234).encode(),
    );
    expect(view!.savedAt, 1234);
  });
}

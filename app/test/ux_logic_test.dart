import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_stats.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/progress_dialog.dart';
import 'package:len/features/documents/templates/page_setup.dart';
import 'package:len/features/library/library_format.dart';

void main() {
  group('library dates', () {
    final now = DateTime(2026, 10, 10, 15, 0);
    int at(DateTime d) => d.millisecondsSinceEpoch;

    test('relative to today', () {
      expect(formatLibraryDate(at(DateTime(2026, 10, 10, 14, 59, 40)), now: now), 'Just now');
      expect(formatLibraryDate(at(DateTime(2026, 10, 10, 9, 5)), now: now), '09:05');
      expect(formatLibraryDate(at(DateTime(2026, 10, 9, 23, 0)), now: now), 'Yesterday');
      expect(formatLibraryDate(at(DateTime(2026, 10, 6, 8, 0)), now: now), 'Tuesday');
      expect(formatLibraryDate(at(DateTime(2026, 9, 3)), now: now), '3 Sep');
      expect(formatLibraryDate(at(DateTime(2024, 9, 3)), now: now), '3 Sep 2024');
    });

    test('page counts', () {
      expect(pageCountLabel(1), '1 page');
      expect(pageCountLabel(12), '12 pages');
    });
  });

  test('page counts per notebook', () {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final a = s.notebooks.create(
      title: 'A',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    s.pages.addPage(a.id, template: const PageTemplate());
    final doomed = s.pages.addPage(a.id, template: const PageTemplate());
    s.pages.delete(doomed.id);
    expect(SurfaceStats(s.database).pageCounts()[a.id], 2);
  });

  test('task progress reports stages, steps and notes', () {
    final p = TaskProgress('Start');
    var notified = 0;
    p.addListener(() => notified++);
    expect(p.fraction, isNull);
    p.step(2, 8, stage: 'Writing PDF…');
    expect(p.stage, 'Writing PDF…');
    expect(p.fraction, 0.25);
    expect(p.detail, 'Page 3 of 8');
    p.stageStarted('Creating pages…', note: '8 pages');
    expect(p.fraction, isNull);
    expect(p.detail, '8 pages');
    expect(notified, 2);
    p.dispose();
  });

  test('task progress can be cancelled: the next step throws', () {
    final p = TaskProgress('Start');
    var notified = 0;
    p.addListener(() => notified++);
    p.step(0, 3);
    p.cancel();
    p.cancel(); // Once is enough.
    expect(p.isCancelled, isTrue);
    expect(notified, 2);
    expect(() => p.step(1, 3), throwsA(isA<Cancelled>()));
    expect(() => p.stageStarted('More'), throwsA(isA<Cancelled>()));
    p.dispose();
  });

  test('template descriptions', () {
    const t = PageTemplate(paper: Paper(PaperStyle.dotted), color: PaperColor.cream);
    expect(describeTemplate(t), 'Dotted · Cream · A4 portrait');
    expect(describeTemplate(t, canvas: true), 'Dotted · Cream · Infinite canvas');
    expect(describeTemplate(t.copyWith(format: PageFormat.square)), 'Dotted · Cream · Square');
  });
}

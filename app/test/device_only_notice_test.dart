import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/library_notice.dart';

class _DaysAgo extends Clock {
  const _DaysAgo(this.days);

  final int days;

  @override
  int nowMs() => DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
}

int _daysAgo(int days) => DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

void main() {
  const title = 'Your notes are only on this device';

  Future<AppServices> pump(
    WidgetTester tester, {
    required bool oldNotes,
    int notesAge = 7,
    Size window = const Size(1280, 800),
    int? lastBackupAt,
  }) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.create(
      AppDatabase.inMemory(),
      clock: oldNotes ? _DaysAgo(notesAge) : const Clock(),
    );
    addTearDown(services.dispose);
    services.settings.lastBackupAt = lastBackupAt;
    services.notebooks.create(
      title: 'Lecture',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(
          home: Scaffold(body: LibraryNotices(child: SizedBox())),
        ),
      ),
    );
    await tester.pump();
    return services;
  }

  testWidgets('without sync, the library says once where notes are', (tester) async {
    final services = await pump(tester, oldNotes: true);
    expect(find.text(title), findsOneWidget);
    expect(find.text('Back up…'), findsOneWidget);
    expect(find.text('Set up sync…'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text(title), findsNothing);
    expect(services.settings.seenTips, contains(LibraryNotices.deviceOnlyTip));
  });

  testWidgets('a backup made elsewhere (Settings) takes the notice down', (tester) async {
    final services = await pump(tester, oldNotes: true);
    expect(find.text(title), findsOneWidget);
    services.settings.lastBackupAt = DateTime.now().millisecondsSinceEpoch;
    services.lenFiles.changed();
    await tester.pump();
    expect(find.text(title), findsNothing);
  });

  testWidgets('not on the first day', (tester) async {
    await pump(tester, oldNotes: false);
    expect(find.text(title), findsNothing);
  });

  testWidgets('not once backed up', (tester) async {
    final services = await pump(tester, oldNotes: true);
    services.settings.lastBackupAt = _daysAgo(0);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(
          home: Scaffold(
            body: LibraryNotices(key: ValueKey('again'), child: SizedBox()),
          ),
        ),
      ),
    );
    expect(find.text(title), findsNothing);
  });

  testWidgets('phones get one line: the short title, Back up… and ✕ (R8-7)', (tester) async {
    await pump(tester, oldNotes: true, window: const Size(390, 844));
    expect(find.text(title), findsNothing);
    expect(find.text('Only on this device'), findsOneWidget);
    expect(find.text('Back up…'), findsOneWidget);
    expect(find.text('Set up sync…'), findsNothing);
    final notice = tester.getSize(find.byType(LibraryNotice));
    expect(notice.height, lessThanOrEqualTo(49));
  });

  testWidgets('comes back once when the last backup is stale (R8-8)', (tester) async {
    final stale = _daysAgo(40);
    final services = await pump(tester, oldNotes: false, lastBackupAt: stale);
    expect(find.text(title), findsOneWidget);
    expect(find.textContaining('Your last backup is from'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(services.settings.seenTips, contains('${LibraryNotices.deviceOnlyTip}@$stale'));
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(
          home: Scaffold(
            body: LibraryNotices(key: ValueKey('again'), child: SizedBox()),
          ),
        ),
      ),
    );
    expect(find.text(title), findsNothing);
  });

  testWidgets('not when nothing changed since a stale backup', (tester) async {
    await pump(tester, oldNotes: true, notesAge: 60, lastBackupAt: _daysAgo(40));
    expect(find.text(title), findsNothing);
  });
}

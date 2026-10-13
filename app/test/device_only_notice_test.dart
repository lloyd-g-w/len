import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/library_notice.dart';

class _LastWeek extends Clock {
  @override
  int nowMs() => DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
}

void main() {
  const title = 'Your notes are only on this device';

  Future<AppServices> pump(WidgetTester tester, {required bool oldNotes}) async {
    final services = AppServices.create(
      AppDatabase.inMemory(),
      clock: oldNotes ? _LastWeek() : const Clock(),
    );
    addTearDown(services.dispose);
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
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text(title), findsNothing);
    expect(services.settings.seenTips, contains(LibraryNotices.deviceOnlyTip));
  });

  testWidgets('not on the first day', (tester) async {
    await pump(tester, oldNotes: false);
    expect(find.text(title), findsNothing);
  });

  testWidgets('not once backed up', (tester) async {
    final services = await pump(tester, oldNotes: true);
    services.settings.lastBackupAt = 1;
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
}

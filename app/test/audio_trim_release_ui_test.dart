import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/ui/recordings_sheet.dart';
import 'package:len/features/documents/export/export_flow.dart' show ExportFile;
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/platform/file_export.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;
import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';

const _t0 = 1000000;
const _part = 300000; // 5 min.
const _mb = 1024 * 1024;

Future<(AppServices, String, List<String>)> _pump(WidgetTester tester) async {
  await loadFonts();
  tester.view
    ..physicalSize = const Size(1280, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final audio = FakeAudio();
  final services = AppServices.create(
    AppDatabase.inMemory(),
    clock: FakeClock()..now = _t0 + 3600000,
    audio: audio.backends,
  );
  addTearDown(services.dispose);
  final nb = services.notebooks.create(
    title: 'Biology lecture',
    kind: NotebookKind.canvas,
    paper: PaperStyle.wideRuled,
    coverColor: 0xFF3B5BDB,
  );
  // A browser recording: three WebM parts of 1, 1 and 2 MB.
  final shas = <String>[];
  for (final (i, size) in [_mb, _mb, 2 * _mb].indexed) {
    final bytes = Uint8List(size)..[0] = i;
    shas.add(await services.blobs.putFile(XFile.fromData(bytes), mime: 'audio/webm'));
  }
  final r = services.recordings.save(
    notebookId: nb.id,
    parts: [for (final sha in shas) RecordingPart(sha, _part)],
    mime: 'audio/webm',
    title: 'Mitosis',
    segments: const [RecordingSegment(_t0, 3 * _part)],
  );
  services.recordings.trim(r.id, 310000, 590000);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (services, r.id, shas);
}

Future<void> _menu(WidgetTester tester) async {
  if (find.byType(RecordingsList).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
  }
  await tester.tap(
    find.descendant(of: find.byType(RecordingsList), matching: find.byTooltip('More')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('free up the space outside a trim: confirm, undo, then for good', (tester) async {
    final (services, id, shas) = await _pump(tester);
    Recording recording() => services.recordings.get(id)!;

    await _menu(tester);
    expect(find.text('4 MB on this device'), findsOneWidget);
    await tester.tap(find.text('Free up 3 MB…'));
    await tester.pumpAndSettle();
    expect(find.text('Free up 3 MB?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Free up'));
    await tester.pumpAndSettle();
    expect(recording().parts.map((p) => p.blob), [shas[1]]);
    expect((recording().trimStartMs, recording().trimEndMs), (10000, 290000));
    expect(find.text('Deleted 3 MB of audio from “Mitosis”'), findsOneWidget);

    // Undo puts the parts (and the trim) back.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(recording().parts.length, 3);
    expect((recording().trimStartMs, recording().trimEndMs), (310000, 590000));

    // Export keeps to the parts the trim touches and says so.
    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
    final list = tester.widget<RecordingsList>(find.byType(RecordingsList));
    List<ExportFile>? exported;
    list.audio.saveFiles = (files, {required mime, toDevice = false, subject}) async {
      exported = files;
      return ExportedFiles(ExportedTo.downloaded, count: files.length);
    };
    await _menu(tester);
    await tester.tap(find.text('Share…'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(exported!.map((f) => f.name), ['Mitosis.webm']);
    expect(exported!.single.bytes.length, _mb);
    expect(find.textContaining('may start earlier or end later than the trim'), findsOneWidget);

    // Freed for good: the menu no longer offers it; a cancelled dialog keeps all.
    await tester.tapAt(const Offset(40, 400)); // Closes the list.
    await tester.pumpAndSettle();
    await _menu(tester);
    await tester.tap(find.text('Free up 3 MB…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(recording().parts.length, 3);
    await _menu(tester);
    await tester.tap(find.text('Free up 3 MB…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Free up'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordingsList), findsNothing);
    await _menu(tester);
    expect(find.textContaining('Free up'), findsNothing);
    expect(find.text('1 MB on this device'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
